FROM ubuntu:20.04

ENV TZ=America/New_York
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install --no-install-recommends -y apt-transport-https build-essential gnupg less sudo ubuntu-server wget zsh
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
  && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update \
  && apt-get install --no-install-recommends -y nodejs postgresql-client-13 \
  && npm install --global npm

WORKDIR /root/adoptopenjdk
RUN wget -O public.crt https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public \
  && gpg --no-default-keyring --keyring ./adoptopenjdk-keyring.gpg --import public.crt \
  && gpg --no-default-keyring --keyring ./adoptopenjdk-keyring.gpg --export --output adoptopenjdk-archive-keyring.gpg \
  && rm adoptopenjdk-keyring.gpg \
  && mv adoptopenjdk-archive-keyring.gpg /usr/share/keyrings \
  && echo "deb [signed-by=/usr/share/keyrings/adoptopenjdk-archive-keyring.gpg] https://adoptopenjdk.jfrog.io/adoptopenjdk/deb focal main" | sudo tee /etc/apt/sources.list.d/adoptopenjdk.list \
  && apt-get update \
  && apt-get install --no-install-recommends -y adoptopenjdk-11-hotspot

# Remove package cache
RUN rm -rf /var/lib/apt/lists/* \
  && apt clean

RUN groupadd --gid 1000 node \
  && useradd --uid 1000 --gid node --shell /bin/zsh --create-home node \
  && usermod --password '$2y$12$c5.ZfEiBNUQSU4xFtsYjpu2YclPKnb1TmQN9V17ZhjS8wIiN8B4lu' node \
  && usermod --append --groups sudo node

USER node
WORKDIR /home/node
ENV ZSH_CUSTOM=/home/node/.oh-my-zsh/custom
RUN sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
  && git clone https://github.com/denysdovhan/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1 \
  && ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
ADD --chown=node:node ../dot-files ./
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d

WORKDIR /flyway
ENV FLYWAY_VERSION 8.0.0-beta1
RUN wget -qO flyway-commandline-${FLYWAY_VERSION}.tar.gz https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz \
  && tar -xzf flyway-commandline-${FLYWAY_VERSION}.tar.gz --strip-components=1 \
  && rm flyway-commandline-${FLYWAY_VERSION}.tar.gz
ENV PATH="/flyway:${PATH}"

CMD [ "zsh" ]
