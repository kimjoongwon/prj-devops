/**
 * buzz-gateway — Jenkins/ArgoCD webhook을 Buzz(Nostr) 채널 메시지로 변환하는 브리지.
 *
 * Slack webhook과 동일한 사용성(URL + JSON POST)을 제공하되, nostr 서명에 필요한
 * 키는 이 프로세스의 환경변수(K8s Secret)에만 존재한다. 호출자(Jenkins 잡,
 * ArgoCD notifications)는 게이트웨이 토큰 하나만 알면 된다.
 *
 * 의존성 없이 node:http + buzz CLI 서브프로세스만 사용한다.
 * 실행: node --experimental-strip-types main.ts (Node 22+, erasable syntax만 사용)
 */

import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { spawn } from 'node:child_process';
import { timingSafeEqual } from 'node:crypto';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const PORT = Number(process.env.PORT ?? 8080);
const TOKEN = process.env.BUZZ_GATEWAY_TOKEN ?? '';
const DEFAULT_CHANNEL = process.env.BUZZ_CHANNEL ?? '';
const BUZZ_BIN = process.env.BUZZ_BIN ?? 'buzz';

// 배포 체인 스레드 매핑: linkKey로 등록한 스레드 루트에 followKey 메시지를 답장으로 묶는다.
// (빌드→범프→배포완료를 한 스레드로; 프로세스 재시작 시 매핑 유실 — 알림은 끊기지 않고 스레드만 풀린다)
const threadLinks = new Map<string, string>();
const THREAD_LINKS_MAX = 300;
function rememberThread(key: string, root: string): void {
  if (threadLinks.size >= THREAD_LINKS_MAX) {
    const oldest = threadLinks.keys().next().value;
    if (oldest !== undefined) threadLinks.delete(oldest);
  }
  threadLinks.set(key, root);
}

// 본문 상한: 빌드 로그 첨부(fileB64)를 감안해 8MB까지. 메시지 본문은 16K로 제한.
const MAX_BODY_BYTES = 8 * 1024 * 1024;
const MAX_CONTENT_CHARS = 16 * 1024;
const MAX_FILE_BYTES = 4 * 1024 * 1024;
const BUZZ_TIMEOUT_MS = 30_000;

// buzz CLI 종료 코드 규약(--help 발췌):
// 0=ok 1=bad input 2=relay/network 3=auth 4=other 5=write conflict
const EXIT_STATUS: Record<number, number> = { 1: 400, 2: 502, 3: 500, 4: 500, 5: 409 };

interface SendBody {
  content?: string;
  /** ArgoCD notifications 템플릿 호환 별칭 */
  message?: string;
  text?: string;
  channel?: string;
  /** 첨부 파일(base64). 예: 빌드 실패 로그 */
  fileB64?: string;
  filename?: string;
  /** hex/npub 공개키. @멘션으로 알림 */
  mentions?: string[];
  /** 이벤트 ID. 지정 시 스레드로 답장 */
  replyTo?: string;
  /** 이 메시지의 스레드 루트를 이 키로 등록 (빌드→범프 체인용) */
  linkKey?: string;
  /** 등록된 키의 스레드에 답장으로 묶는다 (배포완료 알림용). replyTo가 없을 때만 동작 */
  followKey?: string;
  /** RFC3339. 둘 다 유효하면 "동기화 소요: N분 N초" 줄을 content 끝에 추가한다 */
  startedAt?: string;
  finishedAt?: string;
}

/** 알림용 소요시간 포맷 (ms → "1시간 2분" / "3분 4초" / "45초") */
function fmtDuration(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return `${s}초`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}분 ${s % 60}초`;
  return `${Math.floor(m / 60)}시간 ${m % 60}분`;
}

function sendJson(res: ServerResponse, status: number, body: Record<string, unknown>): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(payload);
}

function authorized(req: IncomingMessage): boolean {
  if (!TOKEN) return false; // 토큰 미설정 쓰기 차단(fail-closed)
  const header = req.headers.authorization ?? '';
  const expected = `Bearer ${TOKEN}`;
  const a = Buffer.from(header);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

function readBody(req: IncomingMessage): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new BodyTooLarge());
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

class BodyTooLarge extends Error {
  constructor() {
    super(`body exceeds ${MAX_BODY_BYTES} bytes`);
  }
}

function sanitizeFilename(name: string | undefined): string {
  const base = (name ?? 'attachment.log').split('/').pop() ?? 'attachment.log';
  return /^[A-Za-z0-9._-]+$/.test(base) ? base : 'attachment.log';
}

function runBuzz(args: string[], stdin?: string): Promise<{ code: number; stdout: string; stderr: string; timedOut: boolean }> {
  return new Promise((resolve) => {
    const child = spawn(BUZZ_BIN, args, { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
    }, BUZZ_TIMEOUT_MS);

    child.stdout.on('data', (d: Buffer) => (stdout += d));
    child.stderr.on('data', (d: Buffer) => (stderr += d));
    child.on('error', (err) => {
      clearTimeout(timer);
      stderr += String(err);
      resolve({ code: 4, stdout, stderr, timedOut });
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code: code ?? 4, stdout, stderr, timedOut });
    });

    if (stdin !== undefined) {
      child.stdin.end(stdin);
    } else {
      child.stdin.end();
    }
  });
}

async function handleSend(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const raw = await readBody(req);
  let parsed: SendBody;
  try {
    parsed = JSON.parse(raw.toString('utf8')) as SendBody;
  } catch {
    sendJson(res, 400, { ok: false, error: 'invalid JSON body' });
    return;
  }

  // ArgoCD webhook 템플릿은 "message"를 쓰기도 한다. 셋 중 하나만 있으면 된다.
  let content = parsed.content ?? parsed.message ?? parsed.text ?? '';
  if (!content.trim()) {
    sendJson(res, 400, { ok: false, error: 'content (또는 message/text) is required' });
    return;
  }
  // startedAt/finishedAt가 오면 동기화 소요시간 줄을 덧붙인다.
  // (argoCD 쪽 템플릿 언어로 시차 계산이 안 되어 게이트웨이가 대신 계산)
  const startedMs = Date.parse(parsed.startedAt ?? '');
  const finishedMs = Date.parse(parsed.finishedAt ?? '');
  if (!Number.isNaN(startedMs) && !Number.isNaN(finishedMs) && finishedMs >= startedMs) {
    content += `\n동기화 소요: ${fmtDuration(finishedMs - startedMs)}`;
  }
  if (content.length > MAX_CONTENT_CHARS) {
    sendJson(res, 400, { ok: false, error: `content exceeds ${MAX_CONTENT_CHARS} chars` });
    return;
  }

  const channel = parsed.channel ?? DEFAULT_CHANNEL;
  if (!channel) {
    sendJson(res, 500, { ok: false, error: 'channel not set (payload.channel 또는 BUZZ_CHANNEL)' });
    return;
  }

  const mentions = Array.isArray(parsed.mentions)
    ? parsed.mentions.filter((m) => typeof m === 'string' && /^[0-9a-zA-Z]+$/.test(m))
    : [];

  // 스레드 묶기: 명시적 replyTo 우선, 없으면 followKey로 등록된 루트에 답장
  let replyTo: string | undefined = parsed.replyTo;
  if (!replyTo && parsed.followKey && /^[0-9a-zA-Z_-]+$/.test(parsed.followKey)) {
    replyTo = threadLinks.get(parsed.followKey);
  }
  if (replyTo && !/^[0-9a-f]{64}$/.test(replyTo)) replyTo = undefined;

  const args = ['messages', 'send', '--channel', channel, '--content', '-'];
  for (const m of mentions) args.push('--mention', m);
  if (replyTo) args.push('--reply-to', replyTo);

  let tmpDir: string | undefined;
  try {
    if (parsed.fileB64) {
      const fileBuf = Buffer.from(parsed.fileB64, 'base64');
      if (fileBuf.length === 0 || fileBuf.length > MAX_FILE_BYTES) {
        sendJson(res, 400, { ok: false, error: `fileB64 decoded size must be 1..${MAX_FILE_BYTES} bytes` });
        return;
      }
      tmpDir = await mkdtemp(join(tmpdir(), 'buzz-gw-'));
      const filePath = join(tmpDir, sanitizeFilename(parsed.filename));
      await writeFile(filePath, fileBuf);
      args.push('--file', filePath);
    }

    const result = await runBuzz(args, content);
    if (result.timedOut) {
      sendJson(res, 504, { ok: false, error: 'buzz CLI timeout' });
      return;
    }
    if (result.code !== 0) {
      const status = EXIT_STATUS[result.code] ?? 500;
      sendJson(res, status, { ok: false, error: `buzz exited ${result.code}`, detail: result.stderr.trim() });
      return;
    }
    // buzz --format json의 stdout(전송된 이벤트)을 그대로 돌려준다.
    let event: { id?: string; event_id?: string } | null = null;
    try {
      event = JSON.parse(result.stdout);
    } catch {
      event = null;
    }
    // linkKey: 이 메시지(또는 답장 대상)의 스레드 루트를 등록
    const rootId = replyTo ?? event?.event_id ?? event?.id;
    if (parsed.linkKey && rootId) {
      rememberThread(parsed.linkKey, rootId);
    }
    sendJson(res, 200, { ok: true, event });
  } finally {
    if (tmpDir) await rm(tmpDir, { recursive: true, force: true }).catch(() => {});
  }
}

const server = createServer((req, res) => {
  const url = req.url ?? '/';
  if (req.method === 'GET' && url === '/healthz') {
    sendJson(res, 200, {
      ok: true,
      channelConfigured: Boolean(DEFAULT_CHANNEL),
      tokenConfigured: Boolean(TOKEN),
    });
    return;
  }
  if (req.method === 'POST' && url === '/send') {
    if (!authorized(req)) {
      sendJson(res, 401, { ok: false, error: 'unauthorized' });
      return;
    }
    handleSend(req, res).catch((err) => {
      if (err instanceof BodyTooLarge) {
        sendJson(res, 413, { ok: false, error: err.message });
        return;
      }
      sendJson(res, 500, { ok: false, error: String(err) });
    });
    return;
  }
  sendJson(res, 404, { ok: false, error: 'not found' });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[buzz-gateway] listening on :${PORT} (channel=${DEFAULT_CHANNEL ? 'set' : 'MISSING'})`);
});

const shutdown = () => {
  console.log('[buzz-gateway] shutting down');
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 5000).unref();
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
