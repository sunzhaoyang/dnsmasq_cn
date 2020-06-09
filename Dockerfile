# for test
FROM --platform=${TARGETPLATFORM:-linux/amd64} golang:alpine as builder

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

ARG TARGETPLATFORM
ARG BUILDPLATFORM

ENV CLOUDFLARED_VERSION="2020.5.1"

RUN apk --update --no-cache add \
    bash \
    build-base \
    gcc \
    git \
  && rm -rf /tmp/* /var/cache/apk/*

RUN git clone --branch ${CLOUDFLARED_VERSION} https://github.com/cloudflare/cloudflared /go/src/github.com/cloudflare/cloudflared
WORKDIR /go/src/github.com/cloudflare/cloudflared
RUN make cloudflared

RUN git clone https://github.com/felixonmars/dnsmasq-china-list.git /tmp/dnsmasq-china-list

FROM --platform=${TARGETPLATFORM:-linux/amd64} alpine:latest

ENV TZ="Asia/Shanghai" \
  TUNNEL_METRICS="0.0.0.0:49312" \
  TUNNEL_DNS_ADDRESS="0.0.0.0" \
  TUNNEL_DNS_PORT="5053" \
  TUNNEL_DNS_UPSTREAM="https://1.1.1.1/dns-query,https://1.0.0.1/dns-query"

RUN apk --update --no-cache add \
    dnsmasq \
    bind-tools \
    ca-certificates \
    libressl \
    shadow \
    tzdata \
  && addgroup -g 1000 cloudflared \
  && adduser -u 1000 -G cloudflared -s /sbin/nologin -D cloudflared \
  && rm -rf /tmp/* /var/cache/apk/*

COPY --from=builder /go/src/github.com/cloudflare/cloudflared/cloudflared /usr/local/bin/cloudflared
COPY --from=builder /tmp/dnsmasq-china-list/*.conf /etc/dnsmasq.d/

RUN cloudflared --version

RUN echo -e " \
no-resolv \n\
server=127.0.0.1#5053 \n\
strict-order \n\
min-cache-ttl=3600 \n\
max-cache-ttl=3600 \n\
conf-dir=/etc/dnsmasq.d,*.conf "> /etc/dnsmasq.conf  

RUN echo -e " /usr/local/bin/cloudflared proxy-dns & \n\
    /usr/sbin/dnsmasq -C /etc/dnsmasq.conf & \n\
    while sleep 60; do \n\
        if ! ps aux |grep -q dnsmasq ;then \n\
        	exit 1 \n\
      	fi \n\
        if ! ps aux |grep -q cloudflared ;then \n\
        	exit 1 \n\
      	fi \n\
    done " > /start.sh && chmod +x /start.sh

EXPOSE 53/udp

ENTRYPOINT ["/bin/sh","-c", "/start.sh"]
