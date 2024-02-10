FROM postgis/postgis:16-3.4

LABEL maintainer="PgOSM Flex - https://github.com/rustprooflabs/pgosm-flex"

ARG OSM2PGSQL_BRANCH=master
ARG OSM2PGSQL_REPO=https://github.com/openstreetmap/osm2pgsql.git


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


WORKDIR /tmp
RUN git clone --depth 1 --branch $OSM2PGSQL_BRANCH $OSM2PGSQL_REPO \
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

RUN wget https://github.com/rustprooflabs/pgdd/releases/download/0.5.1/pgdd_0.5.1_postgis_pg16_amd64.deb \
    && dpkg -i ./pgdd_0.5.1_postgis_pg16_amd64.deb \
    && rm ./pgdd_0.5.1_postgis_pg16_amd64.deb \
    && wget https://github.com/rustprooflabs/convert/releases/download/0.0.3/convert_0.0.3_postgis_pg16_amd64.deb \
    && dpkg -i ./convert_0.0.3_postgis_pg16_amd64.deb \
    && rm ./convert_0.0.3_postgis_pg16_amd64.deb



WORKDIR /app
COPY . ./

RUN pip install --upgrade pip && pip install -r requirements.txt
