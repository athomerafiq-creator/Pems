#!/bin/sh
# Fresh local database → stub → schema → security tests
P="psql -h /tmp/pg -p 5433 -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists t" -c "create database t" >/dev/null 2>&1
$P -d t -f tests/supabase_stub.sql >/dev/null 2>&1 || { echo stub failed; exit 1; }
$P -d t -f supabase/schema.sql 2>&1 | grep -i error && exit 1
python3 tests/rls_test.py
