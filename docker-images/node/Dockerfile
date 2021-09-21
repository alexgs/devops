FROM ubuntu:20.04

ENV TZ=America/New_York
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install --no-install-recommends -y build-essential ubuntu-server wget
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
  && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update \
  && apt-get install --no-install-recommends -y less nodejs postgresql-client-13 sudo zsh \
  && npm install --global npm
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

CMD [ "zsh" ]
