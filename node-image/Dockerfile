FROM ubuntu:20.04

ENV TZ=America/New_York
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

    # TODO Join these commands together so they form a single layer
RUN apt-get update && \
    apt-get upgrade -y
RUN apt-get install --no-install-recommends -y build-essential ubuntu-server wget
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update && \
#    apt-get upgrade -y && \
    apt-get install --no-install-recommends -y nodejs postgresql-client-13 zsh && \
    npm install --global npm

#RUN apt-get update && \
#    apt-get upgrade -y

    # Remove package cache
RUN rm -rf /var/lib/apt/lists/* && \
    apt clean


# USER node

# alexgs:$2y$12$c5.ZfEiBNUQSU4xFtsYjpu2YclPKnb1TmQN9V17ZhjS8wIiN8B4lu

CMD node
