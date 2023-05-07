FROM postgis/postgis:15-3.3

LABEL maintainer="PgOSM Flex - https://github.com/rustprooflabs/pgosm-flex"

ARG OSM2PGSQL_BRANCH=master

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
        postgresql-server-dev-15 \
        curl unzip \
        postgresql-15-pgrouting \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://luarocks.org/releases/luarocks-3.9.1.tar.gz \
    && tar zxpf luarocks-3.9.1.tar.gz \
    && cd luarocks-3.9.1 \
    && ./configure && make && make install

RUN curl -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py \
    && python3 /tmp/get-pip.py \
    && rm /tmp/get-pip.py

RUN luarocks install inifile
RUN luarocks install luasql-postgres PGSQL_INCDIR=/usr/include/postgresql/


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
    && apt autoremove -y \
    && cd /tmp && rm -r /tmp/osm2pgsql


COPY ./sqitch.conf /etc/sqitch/sqitch.conf

WORKDIR /app
COPY . ./

RUN pip install --upgrade pip && pip install -r requirements.txt
