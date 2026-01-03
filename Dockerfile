# 18-3.6 is Debian Trixie (13)
FROM postgis/postgis:18-3.6

LABEL maintainer="PgOSM Flex - https://github.com/rustprooflabs/pgosm-flex"

ARG OSM2PGSQL_BRANCH=master
ARG OSM2PGSQL_REPO=https://github.com/osm2pgsql-dev/osm2pgsql.git


RUN apt-get update \
    # Removed upgrade per https://github.com/rustprooflabs/pgosm-flex/issues/322
    #&& apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        sqitch wget ca-certificates \
        git make cmake g++ \
        libboost-dev libboost-system-dev \
        libboost-filesystem-dev libexpat1-dev zlib1g-dev \
        libbz2-dev libpq-dev libproj-dev lua5.4 liblua5.4-dev \
        python3 python3.13-venv \
        postgresql-server-dev-18 \
        curl unzip \
        postgresql-18-pgrouting \
        nlohmann-json3-dev \
        osmium-tool \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://luarocks.org/releases/luarocks-3.9.2.tar.gz \
    && tar zxpf luarocks-3.9.2.tar.gz \
    && cd luarocks-3.9.2 \
    && ./configure && make && make install

RUN python3 -m venv /venv 
ENV PATH="/venv/bin:$PATH"

RUN curl -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py \
    && python /tmp/get-pip.py \
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

RUN wget https://github.com/rustprooflabs/pgdd/releases/download/0.6.1/pgdd_0.6.1_postgis_pg18_amd64.deb \
    && dpkg -i ./pgdd_0.6.1_postgis_pg18_amd64.deb \
    && rm ./pgdd_0.6.1_postgis_pg18_amd64.deb \
    && wget https://github.com/rustprooflabs/convert/releases/download/0.1.0/convert_0.1.0_postgis_pg18_amd64.deb \
    && dpkg -i ./convert_0.1.0_postgis_pg18_amd64.deb \
    && rm ./convert_0.1.0_postgis_pg18_amd64.deb


WORKDIR /app
COPY . ./

RUN pip install --upgrade pip && pip install -r requirements.txt
