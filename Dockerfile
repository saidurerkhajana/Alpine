FROM alpine:3.22

RUN apk add --no-cache \
    nginx \
    php84 \
    php84-fpm \
    php84-mysqli \
    php84-pdo \
    php84-pdo_mysql \
    php84-mbstring \
    php84-openssl \
    php84-curl \
    php84-xml \
    php84-zip \
    php84-bcmath \
    php84-tokenizer \
    php84-phar \
    php84-session \
    php84-fileinfo \
    php84-dom \
    php84-ctype \
    php84-json \
    php84-opcache \
    curl \
    git \
    unzip
