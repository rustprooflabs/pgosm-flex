"""

Usage:
	python3 osm2pgsql_recommendation.py colorado 8
"""
import os
import sys
import requests

# Get run-time options
region_name = sys.argv[1]
system_ram_gb = sys.argv[2]
output_path = sys.argv[3]
pgosm_layer_set = sys.argv[4]

# Always renamed to -latest at runtime for MD5 validation
#  taking advantage of that here to simplify
pbf_filename = f'{region_name}-latest'

pbf_file = f'{pbf_filename}.osm.pbf'
print(pbf_file)

osm_pbf_gb = os.path.getsize(pbf_file) / 1024 / 1024 / 1024	

# PgOSM-Flex currently does not support/test append mode.
append = False

api_endpoint = 'https://osm2pgsql-tuner.com/api/v1'
api_endpoint += f'?system_ram_gb={system_ram_gb}'
api_endpoint += f'&osm_pbf_gb={osm_pbf_gb}'
api_endpoint += f'&append={append}'
api_endpoint += f'&pbf_filename={pbf_filename}'
api_endpoint += f'&pgosm_layer_set={pgosm_layer_set}'

headers = {"User-Agent": 'PgOSM-Flex-Docker'}
result = requests.get(api_endpoint, headers=headers)
print(f'Status code: {result.status_code}')

rec = result.json()['osm2pgsql']

osm2pgsql_cmd = rec['cmd']
osm2pgsql_cmd = osm2pgsql_cmd.replace('~/pgosm-data/', output_path)
osm2pgsql_cmd = osm2pgsql_cmd.replace('-d $PGOSM_CONN', '-U postgres -d pgosm')
#print(f"\nCommand:\n{ osm2pgsql_cmd } ")

script_filename = f'osm2pgsql-{region_name}.sh'
osm2pgsql_script_path = os.path.join(output_path, script_filename)

with open(osm2pgsql_script_path,'w') as out_script:
	out_script.write(osm2pgsql_cmd)

