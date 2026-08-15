FROM alpine:3.22

RUN apk add --no-cache \
  nginx \
  curl \
  git \
  bash \
  tar \
  unzip \
  zip \
  mariadb-client \
  redis \
  php84 \
  php84-fpm \
  php84-cli \
  php84-curl \
  php84-mbstring \
  php84-openssl \
  php84-pdo \
  php84-pdo_mysql \
  php84-mysqli \
  php84-gd \
  php84-zip \
  php84-bcmath \
  php84-xml \
  php84-tokenizer \
  php84-fileinfo \
  php84-phar \
  php84-posix \
  php84-simplexml \
  php84-sodium \
  php84-iconv 

CMD ["sleep", "infinity"]
