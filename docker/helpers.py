"""Generic functions used in multiple modules.
"""
import datetime
import logging
import subprocess
import sys


def get_today():
    """Returns yyyy-mm-dd formatted string for today.

    Retunrs
    -------------------------
    today : str
    """
    today = datetime.datetime.today().strftime('%Y-%m-%d')
    return today


def verify_checksum(md5_file, path):
    """If verfication fails calls `sys.exit()`

    Parameters
    ---------------------
    md5_file : str
    path : str
        Path to directory with `md5_file` to validate
    """
    logger = logging.getLogger('pgosm-flex')
    logger.debug(f'Validating {md5_file} in {path}')

    output = subprocess.run(['md5sum', '-c', md5_file],
                            text=True,
                            check=False,
                            cwd=path,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)

    if output.returncode != 0:
        err_msg = f'Failed to validate md5sum. Return code: {output.returncode} {output.stdout}'
        logger.error(err_msg)
        sys.exit(err_msg)

    logger.info(f'md5sum validated')
