FROM postgis/postgis:16-3.4

LABEL maintainer="PgOSM Flex - https://github.com/rustprooflabs/pgosm-flex"

ARG OSM2PGSQL_BRANCH=master
ARG BOUNCER_VERSION=1.21.0

RUN apt-get update \
    # Removed upgrade per https://github.com/rustprooflabs/pgosm-flex/issues/322
    #&& apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        sqitch wget ca-certificates \
        git make cmake g++ \
        libboost-dev libboost-system-dev \
        libboost-filesystem-dev libexpat1-dev zlib1g-dev \
        libbz2-dev libpq-dev libproj-dev lua5.4 liblua5.4-dev \
        python3 python3-distutils \
        postgresql-server-dev-16 \
        curl unzip \
        postgresql-16-pgrouting \
        nlohmann-json3-dev \
        pkg-config libevent-2.1-7 libevent-dev libudns-dev \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://luarocks.org/releases/luarocks-3.9.2.tar.gz \
    && tar zxpf luarocks-3.9.2.tar.gz \
    && cd luarocks-3.9.2 \
    && ./configure && make && make install

RUN curl -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py \
    && python3 /tmp/get-pip.py \
    && rm /tmp/get-pip.py

RUN luarocks install inifile
RUN luarocks install luasql-postgres PGSQL_INCDIR=/usr/include/postgresql/

# pgBouncer implementation based on: https://github.com/edoburu/docker-pgbouncer/blob/master/Dockerfile
RUN   curl -o  /tmp/pgbouncer-$BOUNCER_VERSION.tar.gz -L https://pgbouncer.github.io/downloads/files/$BOUNCER_VERSION/pgbouncer-$BOUNCER_VERSION.tar.gz \
  && cd /tmp \
  && tar xvfz /tmp/pgbouncer-$BOUNCER_VERSION.tar.gz \
  && cd pgbouncer-$BOUNCER_VERSION \
  && ./configure --prefix=/usr --with-udns \
  && make \
  && cp pgbouncer /usr/bin \
  && mkdir -p /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer \
  && cp etc/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini.example \
  && cp etc/userlist.txt /etc/pgbouncer/userlist.txt.example \
  && touch /etc/pgbouncer/userlist.txt \
  && chown -R postgres /var/run/pgbouncer /etc/pgbouncer

WORKDIR /tmp
RUN git clone --depth 1 --branch $OSM2PGSQL_BRANCH https://github.com/openstreetmap/osm2pgsql.git \
    && mkdir osm2pgsql/build \
    && cd osm2pgsql/build \
    && cmake .. -D USE_PROJ_LIB=6 \
    && make -j$(nproc) \
    && make install \
    && apt remove -y \
        make cmake g++ \
        libexpat1-dev zlib1g-dev \
        libbz2-dev libproj-dev \
        curl \
        pkg-config libevent-dev \
    && apt autoremove -y \
    && cd /tmp && rm -r /tmp/osm2pgsql

RUN wget https://github.com/rustprooflabs/pgdd/releases/download/0.5.1/pgdd_0.5.1_postgis_pg16_amd64.deb \
    && dpkg -i ./pgdd_0.5.1_postgis_pg16_amd64.deb \
    && rm ./pgdd_0.5.1_postgis_pg16_amd64.deb \
    && wget https://github.com/rustprooflabs/convert/releases/download/0.0.3/convert_0.0.3_postgis_pg16_amd64.deb \
    && dpkg -i ./convert_0.0.3_postgis_pg16_amd64.deb \
    && rm ./convert_0.0.3_postgis_pg16_amd64.deb



WORKDIR /app
COPY . ./

RUN pip install --upgrade pip && pip install -r requirements.txt
