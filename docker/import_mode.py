"""Import Mode provides class to ease logic related to various import modes.
"""
import sys
import logging


class ImportMode():
    """Determines logical variables used to control program flow.

    WARNING:  The values for `append_first_run` and `replication_update`
    are used to determine when to drop the local DB.  Be careful with any
    changes to these values.
    """
    def __init__(self, replication, replication_update, update):
        """Computes two variables, slim_no_drop and append_first_run
        based on inputs.

        Parameters
        --------------------------
        replication : bool
        replication_update : bool
        update : str
        """
        self.logger = logging.getLogger('pgosm-flex')
        self.replication = replication
        self.replication_update = replication_update
        valid_update_options = ['append', 'create', None]

        if update not in valid_update_options:
            raise ValueError(f'Invalid option for --update. Valid options: {valid_update_options}')

        self.update = update
        self.set_slim_no_drop()
        self.set_append_first_run()


    def set_append_first_run(self):
        if self.replication_update:
            self.append_first_run = False
        else:
            self.append_first_run = True

        if self.update is not None:
            if self.update == 'create':
                self.append_first_run = True
            else:
                self.append_first_run = False

    def set_slim_no_drop(self):
        self.slim_no_drop = False

        if self.replication:
            self.slim_no_drop = True

        if self.update is not None:
            self.slim_no_drop = True


def get_import_mode(replication, schema_name, update):
    """

    Returns
    --------------------------
    import_mode : dict
        Various variables used to control program flow for various import modes.

        Keys:
            slim_no_drop : bool
            append_first_run : bool
            replication : bool
            replication_update : bool
    """
    # Starting to address issues identified in
    # https://github.com/rustprooflabs/pgosm-flex/issues/275
    slim_no_drop = False
    append_first_run = None


    import_mode = {'slim_no_drop': slim_no_drop,
                   'append_first_run': append_first_run,
                   'replication': replication,
                   'replication_update': replication_update,
                   }
    return import_mode
