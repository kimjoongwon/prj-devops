{{/* argocd-webhook-proxy의 nginx 설정 — ConfigMap 본체와 Deployment의
     checksum/nginx-conf 어노테이션이 같은 정의를 공유한다. */}}
{{- define "argocdWebhookProxy.nginxConf" -}}
server {
  listen 8080;
  location / {
    proxy_pass http://argocd-server.argocd.svc.cluster.local:80;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
  # Jenkins push-router(GWT) — /api/jenkins-webhook/generic-webhook-trigger/invoke?token=...
  # trailing slash 프록시라 location 프리픽스가 벗겨져 Jenkins에 그대로 전달된다.
  location /api/jenkins-webhook/ {
    proxy_pass http://jenkins.devops-tools.svc.cluster.local:8080/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
{{- end -}}
