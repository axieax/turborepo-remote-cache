ARG PNPM_VERSION=10.33.0+sha512.10568bb4a6afb58c9eb3630da90cc9516417abebd3fabbe6739f0ae795728da1491e9db5a544c76ad8eb7570f5c4bb3d6c637b2cb41bfdcdb47fa823c8649319
ARG NODE_VERSION=24-alpine@sha256:feb76650b7195319268c59cb2d419c732d6c499b13bf5296f16ab59eb1f0a4f3

FROM node:${NODE_VERSION} AS dependencies
ARG PNPM_VERSION
ENV HOME=/opt/app
ENV CI=true
ARG PACKAGE_VERSION
ENV PACKAGE_VERSION=$PACKAGE_VERSION
RUN addgroup -g 1001 app && adduser -u 1001 -D -G app -s /bin/false app
WORKDIR $HOME
RUN chown app:app $HOME
USER root
RUN corepack enable && corepack prepare pnpm@${PNPM_VERSION} --activate
USER app

FROM dependencies AS build
COPY --chown=app:app package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile --ignore-scripts
COPY --chown=app:app . .
RUN pnpm build:docker

FROM dependencies AS production-dependencies
COPY --chown=app:app package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --prod --frozen-lockfile --ignore-scripts

FROM node:${NODE_VERSION}
RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache tini && \
    rm -rf /var/cache/apk/*
RUN rm -rf /usr/local/lib/node_modules /opt/yarn-v* && \
    rm -f /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/yarn \
    /usr/local/bin/yarnpkg /usr/local/bin/corepack /usr/local/bin/pnpm /usr/local/bin/pnpx
RUN addgroup -g 1001 app && adduser -u 1001 -D -G app -s /bin/false app
WORKDIR /opt/app
COPY --chown=app:app --from=build /opt/app/dist ./dist
COPY --chown=app:app --from=production-dependencies /opt/app/node_modules ./node_modules
COPY --chown=app:app --from=build /opt/app/package.json ./
ARG PACKAGE_VERSION
ENV PACKAGE_VERSION=$PACKAGE_VERSION
USER app
ENV NODE_ENV=production
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "--enable-source-maps", "dist/index.js"]
