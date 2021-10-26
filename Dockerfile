FROM postgis/postgis:14-3.1

LABEL maintainer="PgOSM-Flex - https://github.com/rustprooflabs/pgosm-flex"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sqitch wget ca-certificates \
        git make cmake g++ \
        libboost-dev libboost-system-dev \
        libboost-filesystem-dev libexpat1-dev zlib1g-dev \
        libbz2-dev libpq-dev libproj-dev lua5.2 liblua5.2-dev \
        python3 python3-distutils python3-psycopg2 \
        postgresql-server-dev-14 \
        curl luarocks \
    && rm -rf /var/lib/apt/lists/*

RUN curl -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py \
    && python3 /tmp/get-pip.py \
    && rm /tmp/get-pip.py

RUN luarocks install inifile
RUN luarocks install luasql-postgres PGSQL_INCDIR=/usr/include/postgresql/


WORKDIR /tmp
RUN git clone git://github.com/openstreetmap/osm2pgsql.git \
    && mkdir osm2pgsql/build \
    && cd osm2pgsql/build \
    && cmake .. \
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

RUN pip install -r requirements.txt
