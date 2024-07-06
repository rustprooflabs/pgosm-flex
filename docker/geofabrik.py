"""This module handles the auto-file handling using Geofabrik's download service.
"""
import logging
import json
import os
import shutil
import subprocess

import helpers


def get_region_filename() -> str:
    """Returns the filename needed to download/manage PBF files based on the
    region/subregion.

    Returns
    ----------------------
    filename : str
    """
    region = os.environ.get('PGOSM_REGION')
    subregion = os.environ.get('PGOSM_SUBREGION')

    base_name = '{}-latest.osm.pbf'
    if subregion is None:
        filename = base_name.format(region)
    else:
        filename = base_name.format(subregion)

    return filename


def prepare_data(out_path: str) -> str:
    """Ensures the PBF file is available.

    Checks if it already exists locally, download if needed,
    and verify MD5 checksum.

    Parameters
    ----------------------
    out_path : str

    Returns
    ----------------------
    pbf_file : str
        Full path to PBF file
    """
    region = os.environ.get('PGOSM_REGION')
    subregion = os.environ.get('PGOSM_SUBREGION')
    pgosm_date = os.environ.get('PGOSM_DATE')

    pbf_filename = get_region_filename()

    pbf_file = os.path.join(out_path, pbf_filename)
    pbf_file_with_date = pbf_file.replace('latest', pgosm_date)

    md5_file = f'{pbf_file}.md5'
    md5_file_with_date = f'{pbf_file_with_date}.md5'

    if pbf_download_needed(pbf_file_with_date, md5_file_with_date, pgosm_date):
        logging.getLogger('pgosm-flex').info('Downloading PBF and MD5 files...')
        download_data(region, subregion, pbf_file, md5_file)
        archive_data(pbf_file, md5_file, pbf_file_with_date, md5_file_with_date)
    else:
        logging.getLogger('pgosm-flex').info('Copying Archived files')
        unarchive_data(pbf_file,
                       md5_file,
                       pbf_file_with_date,
                       md5_file_with_date)

    helpers.verify_checksum(md5_file, out_path)
    set_date_from_metadata(pbf_file=pbf_file)

    return pbf_file


def set_date_from_metadata(pbf_file: str):
    """Use `osmium fileinfo` to set a more accurate date to represent when it was
    extracted from OpenStreetMap.

    Parameters
    ---------------------
    pbf_file : str
        Full path to the `.osm.pbf` file.
    """
    logger = logging.getLogger('pgosm-flex')
    osmium_cmd = f'osmium fileinfo {pbf_file} --json'
    output = []
    returncode = helpers.run_command_via_subprocess(cmd=osmium_cmd.split(),
                                                    cwd=None,
                                                    output_lines=output,
                                                    print_to_log=False)
    if returncode != 0:
        logger.error(f'osmium fileinfo failed.  Output: {output}')

    output_joined = json.loads(''.join(output))
    meta_options = output_joined['header']['option']

    try:
        meta_timestamp = meta_options['timestamp']
    except KeyError:
        try:
            meta_timestamp = meta_options['osmosis_replication_timestamp']
        except KeyError:
            meta_timestamp = None

    logger.info(f'PBF Meta timestamp: {meta_timestamp}')
    os.environ['PBF_TIMESTAMP'] = meta_timestamp


def pbf_download_needed(pbf_file_with_date: str, md5_file_with_date: str,
                        pgosm_date: str) -> bool:
    """Decides if the PBF/MD5 files need to be downloaded.

    Parameters
    -------------------------------
    pbf_file_with_date : str
    md5_file_with_date : str
    pgosm_date : str

    Returns
    --------------------------
    download_needed : bool
    """
    logger = logging.getLogger('pgosm-flex')
    # If the PBF file exists, check for the MD5 file too.
    if os.path.exists(pbf_file_with_date):
        logger.info(f'PBF File exists {pbf_file_with_date}')

        if os.path.exists(md5_file_with_date):
            logger.info('PBF & MD5 files exist.  Download not needed')
            download_needed = False
        else:
            if pgosm_date == helpers.get_today():
                print('PBF for today available but not MD5... download needed')
                download_needed = True
            else:
                err = f'Missing MD5 file for {pgosm_date}. Cannot validate.'
                logger.error(err)
                raise FileNotFoundError(err)
    else:
        if not pgosm_date == helpers.get_today():
            err = f'Missing PBF file for {pgosm_date}. Cannot proceed.'
            logger.error(err)
            raise FileNotFoundError(err)

        logger.info('PBF file not found locally. Download required')
        download_needed = True

    return download_needed


def get_pbf_url(region: str, subregion: str) -> str:
    """Returns the URL to the PBF for the region / subregion.

    Parameters
    ----------------------
    region : str
    subregion : str

    Returns
    ----------------------
    pbf_url : str
    """
    base_url = 'https://download.geofabrik.de'

    if subregion is None:
        pbf_url = f'{base_url}/{region}-latest.osm.pbf'
    else:
        pbf_url = f'{base_url}/{region}/{subregion}-latest.osm.pbf'

    return pbf_url


def download_data(region: str, subregion: str, pbf_file: str, md5_file: str):
    """Downloads PBF and MD5 file using wget.

    Parameters
    ---------------------
    region : str
    subregion : str
    pbf_file : str
    md5_file : str
    """
    logger = logging.getLogger('pgosm-flex')
    logger.info(f'Downloading PBF data to {pbf_file}')
    pbf_url = get_pbf_url(region, subregion)

    subprocess.run(
        ['/usr/bin/wget', pbf_url,
         "-O", pbf_file , "--quiet"
        ],
        capture_output=True,
        text=True,
        check=True
    )

    logger.info(f'Downloading MD5 checksum to {md5_file}')
    subprocess.run(
        ['/usr/bin/wget', f'{pbf_url}.md5',
         "-O", md5_file , "--quiet"
        ],
        capture_output=True,
        text=True,
        check=True
    )


def archive_data(pbf_file: str, md5_file: str, pbf_file_with_date: str,
                 md5_file_with_date: str):
    """Copies `pbf_file` and `md5_file` to `pbf_file_with_date` and
    `md5_file_with_date`.

    If either file exists, does nothing.

    Parameters
    --------------------------------
    pbf_file : str
    md5_file : str
    pbf_file_with_date : str
    md5_file_with_date : str
    """
    if os.path.exists(pbf_file_with_date):
        pass
    else:
        shutil.copy2(pbf_file, pbf_file_with_date)

    if os.path.exists(md5_file_with_date):
        pass
    else:
        shutil.copy2(md5_file, md5_file_with_date)


def unarchive_data(pbf_file: str, md5_file: str, pbf_file_with_date: str,
                   md5_file_with_date: str):
    """Copies `pbf_file_with_date` and `md5_file_with_date`
    to `pbf_file` and `md5_file`.

    Always copies, will overwrite a -latest file if it is in the way.

    Parameters
    --------------------------------
    pbf_file : str
    md5_file : str
    pbf_file_with_date : str
    md5_file_with_date : str
    """
    logger = logging.getLogger('pgosm-flex')
    if os.path.exists(pbf_file):
        logger.debug(f'{pbf_file} exists. Overwriting.')

    logger.debug(f'Copying {pbf_file_with_date} to {pbf_file}')
    shutil.copy2(pbf_file_with_date, pbf_file)

    if os.path.exists(md5_file):
        logger.debug(f'{md5_file} exists. Overwriting.')

    logger.debug(f'Copying {md5_file_with_date} to {md5_file}')
    shutil.copy2(md5_file_with_date, md5_file)


def remove_latest_files(out_path: str):
    """Removes the PBF and MD5 file with -latest in the name.

    Files are archived via prepare_data() before processing starts

    Parameters
    -------------------------
    out_path : str
    """
    pbf_filename = get_region_filename()

    pbf_file = os.path.join(out_path, pbf_filename)
    md5_file = f'{pbf_file}.md5'
    logging.debug(f'Removing {pbf_file}')
    os.remove(pbf_file)
    logging.debug(f'Removing {md5_file}')
    os.remove(md5_file)
