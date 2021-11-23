"""Generic functions used in multiple modules.
"""
import datetime
import subprocess


def get_today():
    """Returns yyyy-mm-dd formatted string for today.

    Retunrs
    -------------------------
    today : str
    """
    today = datetime.datetime.today().strftime('%Y-%m-%d')
    return today


def verify_checksum(md5_file, out_path):
    """If verfication fails, raises `CalledProcessError`

    Parameters
    ---------------------
    md5_file : str
    out_path : str
    """
    subprocess.run(['md5sum', '-c', md5_file],
                   capture_output=True,
                   text=True,
                   check=True,
                   cwd=out_path)
