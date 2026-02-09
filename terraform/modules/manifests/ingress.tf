
# RobotShop Web Ingress

resource "kubectl_manifest" "robotshop_web_ingress" {
  yaml_body = <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: robotshop-web
  namespace: app-space
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
    nginx.ingress.kubernetes.io/proxy-set-headers: "ingress-nginx/custom-headers"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - mubashir.site
      secretName: mubashir-site-tls
  rules:
    - host: mubashir.site
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 8080
EOF
}



resource "kubectl_manifest" "configmap-https" {
  yaml_body = <<EOF

apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-headers
  namespace: ingress-nginx
data:
  X-Forwarded-Proto: "https"

EOF
}


resource "kubectl_manifest" "robotshop_config" {
  yaml_body = <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-nginx-config
  namespace: app-space
data:
  default.conf: |
    server {
      listen 8080;
      server_name mubashir.site;

      proxy_http_version 1.1;

      root /usr/share/nginx/html;
      index index.html;

      location ^~ /api/catalogue/ {
          proxy_pass http://catalogue:8080/;
      }

      location ^~ /api/user/ {
          proxy_pass http://user:8080/;
      }

      location ^~ /api/cart/ {
          proxy_pass http://cart:8080/;
      }

      location ^~ /api/shipping/ {
          rewrite ^/api/shipping/?(.*)$ /$1 break;
          proxy_pass http://shipping:8080/shipping/;
      }

      location ^~ /api/payment/ {
          rewrite ^/api/payment/?(.*)$ /$1 break;
          proxy_pass http://payment:8080/payment/;
      }

      location ^~ /api/ratings/ {
          proxy_pass http://ratings:80/;
      }

      # PROXY ALL WEB REQUESTS TO NODE (same Pod)
      location / {
          proxy_pass http://127.0.0.1:3000;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
      }

      # STATIC FILES (images) ALSO TO NODE
      location /images/ {
          proxy_pass http://127.0.0.1:3000;
          proxy_set_header Host "localhost";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
      }
    }
EOF
}

resource "kubectl_manifest" "canary_ingress" {
  yaml_body = <<EOF

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-canary
  namespace: app-space
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "80"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: mubashir.site
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-2
            port:
              number: 8080
EOF
}
