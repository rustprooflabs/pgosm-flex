"""Import Mode provides class to ease logic related to various import modes.
"""
import logging
import json


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
        update : str or None
            Valid options are 'create' or 'append', lining up with osm2pgsql's
            `--create` and `--append` modes.
        """
        self.logger = logging.getLogger('pgosm-flex')
        self.replication = replication
        self.replication_update = replication_update

        # The input via click should enforce this, still worth checking here
        valid_update_options = ['append', 'create', None]

        if update not in valid_update_options:
            raise ValueError(f'Invalid option for --update. Valid options: {valid_update_options}')

        self.update = update
        self.set_slim_no_drop()
        self.set_append_first_run()
        self.set_run_post_sql()


    def set_append_first_run(self):
        """Uses `replication_update` and `update` to determine value for
        `self.append_first_run`
        """
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
        """Uses `replication` and `update` to determine value for
        `self.slim_no_drop`
        """
        self.slim_no_drop = False

        if self.replication:
            self.slim_no_drop = True

        if self.update is not None:
            self.slim_no_drop = True

    def set_run_post_sql(self):
        """Uses `update` value to determine value for
        `self.run_post_sql`.  This value determines if the post-processing SQL
        should be executed.

        Note:  Not checking replication/replication_update because subsequent
        imports use osm2pgsql-replication, which does not attempt to run
        the post-processing SQL scripts.
        """
        self.run_post_sql = True

        if self.update is not None:
            if self.update == 'append':
                self.run_post_sql = False

    def as_json(self):
        """Returns key details as a dictionary.
        """
        self_as_dict = {'update': self.update,
                'replication': self.replication,
                'replication_update': self.replication_update,
                'append_first_run': self.append_first_run,
                'slim_no_drop': self.slim_no_drop,
                'run_post_sql': self.run_post_sql}
        return json.dumps(self_as_dict)

