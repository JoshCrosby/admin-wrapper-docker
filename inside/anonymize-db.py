#!/usr/bin/env python3
# vim:set expandtab ts=4 sw=4 ai ft=python:
"""
Run by `pgdba-anonymize`.  This is the inner guts of the anonymizer.  The assumption when this runs is we have a DB and this
script anonymizes the db in place.

How it works:

* You have a source and destination DB.  The destination can be specified as -, which tells it to not restore (no destination)
* pgdba-anonymize does a lot of the orchestration, calling anonymize-db.py as one step.
* The high level process:
  * The source DB is exported to $BKVOL (defaults to inside the container)
  * The source DB is imported to an internal temporary db (inside the container)
  * The internal temporary DB is anonymized with anonymize-db.py
  * The internal temporary DB is exported to $BKVOL
  * If there is a destination, the anonymized export is then restored into the destination DB

User mappings are static and inline.  This can be improved (see code)
"""

import datetime
import os
import time
import random
import string
import uuid
import nameparser
import faker
import psycopg2
import psycopg2.extras
import dictlib
import postal_address

################################################################################
fake = faker.Faker()
fake.seed(1138) # creates semi-predictable results.  Is this a GDPR problem? -BJG

# we could convert these to Faker.generators if we ever cared to do so...
def fake_auth0_token():
    return "auth0|fake{}".format(random_uuid())

def fake_email():
    return fake.word() + "@example.com"

def fake_phone():
    return "+1801555{}".format(random_number_string(4))

def fake_picture():
    return "https://website/-Bratton.jpg"

def random_card_token():
    return "001.P.{}".format(random_uuid())

def random_device_token():
    return random_string(128)

def random_string(size):
    return ''.join(random.choice(string.ascii_letters) for i in range(size))

def random_number_string(size):
    number_string = ""
    for _ in range(0, size):
        number_string = "{}{}".format(number_string, random_digit())
    return number_string

def random_letter():
    return random.choice(string.ascii_uppercase)

def random_digit():
    return random.randint(0, 9)

def random_date():
    return fake.date_between_dates(date_start=datetime.date.today()).strftime("%Y-%m-%d")

def random_uuid():
    return str(uuid.uuid4())

################################################################################

def get_random(history, get_func, *args):
    """Choose something random, but don't repeat - check against a history"""
    new_name = get_func(*args)
    attempts = -20
    while history.get(new_name):
        new_name = get_func(*args)
        attempts -= 1
        if attempts >= 20: # try adding digits 20 times first
            raise Exception("Exhausted random names for {}".format(get_func))
        if attempts >= 0:
            new_name = "{}{}".format(new_name, str(attempts))

    history[new_name] = True
    return new_name

# debug and log outputs
_DEBUG = os.environ.get('DEBUG', False)
def debug(*args):
    if _DEBUG:
        print("debug>> " + args[0].format(*args[1:]))

def log(msg, *args):
    msg = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
#    if hdr:
#        msg = "> " + msg
#    else:
#        msg = "    " + msg
    print(msg.format(*args))

# this is kindof a hack, but it keeps null values in the DB which may be useful
# for debugging purpose.
def set_if_defined(dobj, key, new):
    if dobj[key] != None:
        if isinstance(new, str):
            dobj[key] = new
        elif callable(new):
            dobj[key] = new()

################################################################################
class AnonDB(object):
    dbc = None

    def __init__(self):
        params = dict(
            dbname=os.environ.get("DATABASE_NAME", ''),
            password=os.environ.get("DATABASE_PASSWORD", ''),
            user=os.environ.get("DATABASE_USERNAME", ''),
            host=os.environ.get("DATABASE_HOST", ''),
            port=os.environ.get("DATABASE_PORT", '')
        )
        log("Anonymizing Database " + params['dbname'])
        self.dbc = psycopg2.connect(**params)
        self.dbc.set_session(autocommit=True)
        debug("Connected to database")

    ############################################################################
    # db helpers
    def query(self, stmt, *args):
        cursor = self.dbc.cursor()
        cursor.execute(stmt, *args)
        return cursor

    # as a dictionary
    def queryd(self, stmt, *args):
        cursor = self.dbc.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cursor.execute(stmt, *args)
        return cursor

    ############################################################################
    def anonymize_zzzies(self):
        log("Anonymizing ZZZ data")

        hist = dict()

        # restructured to use iterator instead of fetchall -BJG
        for row in self.query("SELECT id, name from ZZZ"):
            new_name = get_random(hist, fake.zzzy)
            debug("{}: {} => {}", row[0], row[1], new_name)
            self.query("UPDATE zzz SET name = %s WHERE id = %s",
                       (new_name, row[0])).close()

    ############################################################################
    def anonymize_users(self):
        log("Anonymizing User data")

        hist = dict()
        for row in self.queryd("""
            SELECT id, name, ...# cols
              FROM users"""):

            user = dictlib.Obj(row) # more readable
            name = nameparser.HumanName(get_random(hist, fake.name))

            orig_name = user.display_name

            set_if_defined(user, 'name', str(name))

            debug("{} => {}", orig_name, name)

            self.query("""
                UPDATE users
                   SET ...
                 WHERE id = %s""",
                       (user.name, ...).close()

    ############################################################################
    def anonymize_addresses(self):
        """
for context: postal_address gives us a lot more than we can handle... and its docs suck.
Long and short, it has a 'subdivision' concept to deal with internationalized addresses.
A couple examples (I just read the test code to figure out what I could - BJG):

            {'district_name': 'Pirojpur',
             'district': Subdivision(code='BD-50',
                                     country_code='BD',
                                     name='Pirojpur',
                                     parent='A',
                                     parent_code='BD-A',
                                     type='District'),
              'division_name': 'Barisal',
              'postal_code': '28455-9089',
              'country_code': 'BD',
              'division': Subdivision(code='BD-A',
                                      country_code='BD',
                                      name='Barisal',
                                      parent_code=None,
                                      type='Division'),
              'division_code': 'BD-A',
              'line1': '9658 Troels Village',
              'line2': 'Excepturi illo itaque ipsam natus est labore.',
              'city_name': 'West Finn',
              'district_code': 'BD-50',
              'division_type_name': 'Division',
              'district_type_name': 'District',
              'subdivision_code': 'BD-50'}

              {'line2': 'Non quidem excepturi illo.',
               'country_code': 'SM',
               'municipalities': Subdivision(code='SM-07',
                                             country_code='SM',
                                             name='San Marino',
                                             parent_code=None,
                                             type='Municipalities'),
               'line1': 'Petřínská 5/8',
               'subdivision_code': 'SM-07',
               'municipalities_name': 'San Marino',
               'postal_code': '563 57',
               'municipalities_type_name': 'Municipalities',
               'municipalities_code': 'SM-07',
               'city_name': 'Stráž pod Ralskem'}

        """

        log("Anonymizing Address data")
        for row in self.queryd("""
            SELECT id, street1, street2, city, state, zip_code, country
              FROM addresses"""):

            addr = postal_address.address.random_address()

            new = (addr.line1,
                   addr.line2,
                   addr.city_name,
                   addr.subdivision_code,
                   addr.postal_code,
                   addr.country_code,
                   row['id'])

            debug("{} => {}", row, new)

            # left out country for now
            self.query("""
                UPDATE addresses
                   SET street1 = %s, street2 = %s, city = %s, state = %s,
                       zip_code = %s, country = %s
                 WHERE id = %s""", new).close()

    ############################################################################
    def anonymize_receipts(self):
        log("Anonymizing Receipt data")

        for row in self.query("SELECT id, name FROM receipts"):
            if row[1]:
                self.query("UPDATE receipts SET name = %s WHERE id = %s",
                           ("{}.jpg".format(random_string(16)), row[0])).close()

    ############################################################################
    def trim_lint(self):
        log("Trimming uneeded data")

        self.query("TRUNCATE table1")
        self.query("TRUNCATE table2")
        self.query("TRUNCATE table3")

    def map_test_users(self, superadmin=None, trans=None, budgets=None, cards=None):
        """
        All users are provided as a list [email, id]
        superadmin is a single user, and only one is set (for superadmin)
        each other attribute (trans, budgets, cards) is a dictionary as:

          {"admin": [email,id],
           "users": [ [email,id], [email,id], ...]}

        1. superadmin is setup as the super admin
        2. trans is mapped as the organization with the most transactions
        3. budgets is mapped as the org with the most budgets (excluding the org from #2)
        4. cards is mapped as org with the most cards (excluding #2 and #3)
        """

        # set super admin.  use 'for' since we are getting an iterator
        for row in self.query("SELECT id FROM users where ... limit 1"):
            self.query("""
                       UPDATE users
                          SET email = %s, auth_info = %s
                        WHERE id = %s""",
                       (superadmin[0], superadmin[1], row[0]))
            log("Super Admin: {}", superadmin[0])
            break # really, we should only have one (limit 1 above)

        # which zzzies have we used?
        history = set()

        for row in self.query("""
            SELECT ...
              FROM ...
             GROUP BY ...
             ORDER BY count DESC
             """):
            if self._map_users(history=history, zzzy=row[0], label="foo", **foo):
                break

    def _map_users(self, history=None, admin=None, users=None, zzzy=0, label=""):
        # skip if we've already mapped them
        if zzzy in history:
            return False
        history.add(zzzy)

        # map out an admin
        for row in self.query("""
            SELECT id
              FROM users
             WHERE zzzy_id = %s AND
                   zzzy_admin = true AND
                   retired = false""", (zzzy,)):
            self.query("""
                       UPDATE users
                          SET email = %s, auth_id = %s
                        WHERE id = %s""",
                       (admin[0], admin[1], row[0]))
            log("most {} zzzy={} admin={}", label, zzzy, admin[0])
            break

        # map out non-admins
        for row in self.query("""
            SELECT id
              FROM users
             WHERE zzzy_id = %s AND
                   zzzy_admin = false AND
                   retired = false""", (zzzy,)):
            # stop once we have exhausted users
            if not users:
                break
            user = users.pop()
            self.query("""
                       UPDATE users
                          SET email = %s, auth_id = %s
                        WHERE id = %s""",
                       (user[0], user[1], row[0]))
            log("most {} zzzy={} user={}", label, zzzy, user[0])

        return True

################################################################################
def main():
    mydb = AnonDB()

    mydb.anonymize_zzzies()
    mydb.anonymize_users()
    mydb.anonymize_addresses()

    mydb.trim_lint()

    mydb.map_test_users(
        superadmin=["dev+super@example.com", "pass1"],
        trans={"admin": ["dev+tadm@example.com", "pass2"],
               "users": [["dev+tusr1@example.com", "pass3"],
                         ["dev+tusr2@example.com", "pass3"],
                         ["dev+tusr3@example.com", "pass3"]]},
        budgets={"admin": ["dev+badm@example.com", "pass3"],
                 "users": [["dev+busr1@example.com", "pass3"],
                           ["dev+busr2@example.com", "pass3"]]},
        cards={"admin": ["dev+cadm@example.com", "pass3"],
               "users": [["dev+cusr1@example.com", "pass3"],
                         ["dev+cusr2@example.com", "pass3"]]}
    )

    mydb.dbc.close()

if __name__ == "__main__":
    main()
