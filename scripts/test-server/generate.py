#!/usr/bin/env python3
"""Writes the LDIF for the large test directory that run.sh loads.

dc=example,dc=com (~151k entries):
  ou=Service            the accounts the app binds as (manager, reader)
  ou=People             76,000 users, all direct children
  ou=Groups             2,000 groups
  ou=Departments        50 departments x 10 teams x 100 users
  ou=Computers          22,000 devices
  ou=Deep               a 30-level chain with a few leaves at every level
  ou=Restricted         readable by nobody but the rootdn (per-node errors)
  ou=Empty              an OU with no children

dc=small,dc=test (a couple of dozen entries) is written to a second file,
to check nothing got worse on a small directory.
"""
import base64
import os
import sys

BASE = "dc=example,dc=com"

# A 1x1 white JPEG, so a few users carry a real binary jpegPhoto.
PHOTO = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP////////////////////////////////////"
    "//////////////////////////////////////////////////wgALCAABAAEBAREA/8QA"
    "FBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA="
)


def entry(out, dn, *attrs):
    out.write(f"dn: {dn}\n")
    for name, value in attrs:
        if isinstance(value, bytes):
            out.write(f"{name}:: {base64.b64encode(value).decode()}\n")
        else:
            out.write(f"{name}: {value}\n")
    out.write("\n")


def ou(out, name, parent):
    entry(out, f"ou={name},{parent}",
          ("objectClass", "organizationalUnit"), ("ou", name))
    return f"ou={name},{parent}"


def person(out, uid, parent, n, photo=False):
    attrs = [
        ("objectClass", "inetOrgPerson"),
        ("uid", uid),
        ("cn", f"User {n:06d}"),
        ("sn", f"{n:06d}"),
        ("givenName", "User"),
        ("mail", f"{uid}@example.com"),
        ("userPassword", "password"),
    ]
    if photo:
        attrs.append(("jpegPhoto", PHOTO))
    entry(out, f"uid={uid},{parent}", *attrs)


def big(path):
    count = 0
    with open(path, "w") as out:
        entry(out, BASE, ("objectClass", "dcObject"),
              ("objectClass", "organization"), ("dc", "example"),
              ("o", "Example Corp"))
        service = ou(out, "Service", BASE)
        for name in ("manager", "reader"):
            entry(out, f"cn={name},{service}",
                  ("objectClass", "organizationalRole"),
                  ("objectClass", "simpleSecurityObject"),
                  ("cn", name), ("userPassword", name))
        count += 4

        people = ou(out, "People", BASE)
        for n in range(76_000):
            person(out, f"user{n:06d}", people, n, photo=n < 5)
        count += 76_001

        groups = ou(out, "Groups", BASE)
        for n in range(2_000):
            members = [f"uid=user{(n * 7 + k) % 76_000:06d},{people}"
                       for k in range(5)]
            entry(out, f"cn=group{n:04d},{groups}",
                  ("objectClass", "groupOfNames"), ("cn", f"group{n:04d}"),
                  *[("member", m) for m in members])
        count += 2_001

        depts = ou(out, "Departments", BASE)
        count += 1
        serial = 0
        for d in range(50):
            dept = ou(out, f"Dept{d:02d}", depts)
            count += 1
            for t in range(10):
                team = ou(out, f"Team{t:02d}", dept)
                count += 1
                for _ in range(100):
                    person(out, f"d{serial:06d}", team, serial)
                    serial += 1
                    count += 1

        computers = ou(out, "Computers", BASE)
        for n in range(22_000):
            entry(out, f"cn=ws{n:05d},{computers}",
                  ("objectClass", "device"), ("cn", f"ws{n:05d}"),
                  ("description", f"Workstation {n}"))
        count += 22_001

        parent = ou(out, "Deep", BASE)
        count += 1
        for level in range(1, 31):
            for leaf in range(3):
                person(out, f"deep{level:02d}x{leaf}", parent, level * 10 + leaf)
                count += 1
            parent = ou(out, f"Level{level:02d}", parent)
            count += 1

        restricted = ou(out, "Restricted", BASE)
        for n in range(10):
            person(out, f"secret{n}", restricted, n)
        count += 11

        ou(out, "Empty", BASE)
        count += 1
    return count


def small(path):
    base = "dc=small,dc=test"
    with open(path, "w") as out:
        entry(out, base, ("objectClass", "dcObject"),
              ("objectClass", "organization"), ("dc", "small"), ("o", "Small"))
        entry(out, f"cn=manager,{base}",
              ("objectClass", "organizationalRole"),
              ("objectClass", "simpleSecurityObject"),
              ("cn", "manager"), ("userPassword", "manager"))
        people = ou(out, "People", base)
        for n in range(12):
            person(out, f"small{n:02d}", people, n, photo=n == 0)
        groups = ou(out, "Groups", base)
        entry(out, f"cn=admins,{groups}", ("objectClass", "groupOfNames"),
              ("cn", "admins"), ("member", f"uid=small00,{people}"))
        ou(out, "Empty", base)


if __name__ == "__main__":
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    n = big(os.path.join(out_dir, "example.ldif"))
    small(os.path.join(out_dir, "small.ldif"))
    print(f"wrote {n} entries for {BASE}")
