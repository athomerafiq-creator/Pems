"""Row-level security tests for PEMS.

Runs against a local PostgreSQL loaded with tests/supabase_stub.sql and
supabase/schema.sql. Each check runs as a signed-in user (role
`authenticated` + JWT subject), exactly like Supabase does.

Usage: python3 tests/rls_test.py "psql -h /tmp/pg -p 5433 -U postgres -d t"
"""
import subprocess, sys, uuid

PSQL = sys.argv[1] if len(sys.argv) > 1 else "psql -h /tmp/pg -p 5433 -U postgres -d t"
fails = 0


def run(sql, uid=None):
    pre = ""
    if uid:
        pre = f"set role authenticated; set request.jwt.claim.sub = '{uid}';\n"
    p = subprocess.run(PSQL.split() + ["-At", "-v", "ON_ERROR_STOP=1", "-c", pre + sql],
                       capture_output=True, text=True)
    return p.returncode == 0, (p.stdout.strip() or p.stderr.strip())


def check(name, ok):
    global fails
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        fails += 1


def val(sql, uid=None):
    ok, out = run(sql, uid)
    if not ok:
        return "ERR:" + out
    return out.splitlines()[-1] if out else ""


# --- users (created as Supabase Auth would) ---
P, A1, A2, X = (str(uuid.uuid4()) for _ in range(4))
for uid, em in [(P, "athomerafiq@gmail.com"), (A1, "pstocoo.ishc@gmail.com"), (A2, "support@revenuehelper.org"), (X, "stranger@example.com")]:
    run(f"insert into auth.users(id,email) values ('{uid}','{em}')")

check("principal profile created", val(f"select role from profiles where id='{P}'") == "principal")
check("PA gets calendar edit", val(f"select level from permissions where user_id='{A1}' and module='calendar'") == "edit")
check("PA02 gets finance entry", val(f"select level from permissions where user_id='{A2}' and module='finance'") == "entry")
check("PA02 workspaces", val(f"select count(*) from workspace_access where user_id='{A2}'") == "2")

# --- principal creates data ---
ok, out = run("""
insert into appointments(title,date,ws,scope) values ('Biz meeting',current_date,'AGL Group','BUSINESS');
insert into appointments(title,date,ws,scope) values ('Doctor',current_date,'Personal Affairs','PERSONAL');
insert into appointments(title,date,ws,scope) values ('Consulting call',current_date,'Consulting & Partnerships','BUSINESS');
insert into transactions(type,category,amount,currency,ws,status) values ('Income','Salary',5000,'USD','Big7Placements','Approved');
insert into staff(name,salary,user_id) values ('Md Sumon Reza',60000,'%s'), ('PA02',45000,'%s'), ('Driver',25000,null);
insert into focus_items(text) values ('secret focus');
""" % (A1, A2), P)
check("principal inserts records", ok)

# --- visibility ---
check("principal sees all 3 appointments", val("select count(*) from appointments", P) == "3")
check("PA sees 2 (no personal)", val("select count(*) from appointments", A1) == "2")
check("PA02 sees 1 (only its workspaces)", val("select count(*) from appointments", A2) == "1")
check("stranger sees nothing", val("select count(*) from appointments", X) == "0")
check("PA cannot see focus items", val("select count(*) from focus_items", A1) == "0")
check("PA cannot see finance", val("select count(*) from transactions", A1) == "0")
check("PA02 cannot see principal's finance", val("select count(*) from transactions", A2) == "0")
check("PA cannot read salaries except own row", val("select count(*) from staff", A1) == "1")

# --- writes ---
ok, _ = run("insert into appointments(title,date,ws,scope) values ('x',current_date,'AGL Group','PERSONAL')", A1)
check("PA cannot create PERSONAL record", not ok)
ok, _ = run("insert into appointments(title,date,ws,scope) values ('x',current_date,'Personal Affairs','BUSINESS')", A1)
check("PA cannot write to a workspace it lacks", not ok)
ok, _ = run("insert into appointments(title,date,ws,scope) values ('PA meeting',current_date,'AGL Group','BUSINESS')", A1)
check("PA can add appointment in its workspace", ok)
ok, _ = run("insert into appointments(title,date,ws,scope) values ('x',current_date,'AGL Group','BUSINESS')", A2)
check("PA02 (calendar view) cannot add appointment", not ok)
ok, _ = run("update appointments set archived=true where title='PA meeting'", A1)
check("PA cannot archive", not ok)
check("PA cannot delete", val("with d as (delete from appointments where title='PA meeting' returning 1) select count(*) from d", A1) == "0")

ok, _ = run("insert into transactions(type,category,amount,currency,ws,status) values ('Expense','Courier',1200,'BDT','AGL Group','Approved')", A2)
check("PA02 can submit expense", ok)
check("PA02 expense forced to Pending", val("select status from transactions where category='Courier'", P) == "Pending")
check("PA02 sees only own entry", val("select count(*) from transactions", A2) == "1")
ok, _ = run("update transactions set status='Approved' where category='Courier'", A2)
check("PA02 cannot approve", not ok)
ok, _ = run("update transactions set status='Approved' where category='Courier'", P)
check("principal approves", ok)
ok, out = run("update transactions set amount=1 where category='Courier' returning id", A2)
check("PA02 cannot edit after approval", (not ok) or out == "" or "UPDATE 0" in out)

# --- tasks ---
run(f"insert into tasks(title,status,assignee,ws) values ('Draft MoU','Review','{A1}','Consulting & Partnerships')", P)
ok, _ = run("update tasks set status='Completed' where title='Draft MoU'", A1)
check("PA cannot approve own review task", not ok)
ok, _ = run("update tasks set status='Completed' where title='Draft MoU'", P)
check("principal approves review task", ok)

# --- attendance ---
ok, _ = run("insert into attendance(user_id,date,check_in) values (auth.uid(),'2020-01-01','05:00')", A1)
check("PA checks in", ok)
check("check-in date/time come from server clock", val("select date<>'2020-01-01' and check_in<>'05:00' from attendance", P) == "t")
ok, _ = run("insert into attendance(user_id,date,check_in) values (auth.uid(),current_date,'09:00')", A1)
check("double check-in blocked", not ok)
check("PA02 cannot see PA's attendance", val("select count(*) from attendance", A2) == "0")
ok, _ = run("update attendance set check_out='23:00' where check_out is null", A1)
check("PA checks out", ok)
ok, _ = run("update attendance set check_in='01:00'", A1)
check("closed entry cannot be changed by PA", (not ok) or val("select check_in from attendance", P) != "01:00")

# --- warnings ---
run(f"insert into warnings(staff_id,grade,reason) select id,'Grade 1','Late' from staff where user_id='{A2}'", P)
run(f"insert into warnings(staff_id,grade,reason) select id,'Grade 2','Other' from staff where name='Driver'", P)
check("PA02 sees only own warning", val("select count(*) from warnings", A2) == "1")
check("PA sees no warnings", val("select count(*) from warnings", A1) == "0")
ok, _ = run("select ack_warning(id) from warnings", A2)
check("PA02 acknowledges own warning", ok)
ok, _ = run("insert into warnings(staff_id,grade,reason) select id,'Grade 3','x' from staff limit 1", A1)
check("PA cannot issue warnings", not ok)

# --- chat ---
dm = "dm:" + ":".join(sorted([P, A1]))
ok, _ = run(f"insert into chat_messages(channel,body) values ('general','hi'),('ws:AGL Group','agl'),('ws:Consulting & Partnerships','cons'),('{dm}','private')", P)
check("principal posts", ok)
check("PA sees general+AGL+Consulting+DM", val("select count(*) from chat_messages", A1) == "4")
check("PA02 sees general+AGL only", val("select count(*) from chat_messages", A2) == "2")
ok, _ = run(f"insert into chat_messages(channel,body) values ('{dm}','sneak')", A2)
check("PA02 cannot post in others' DM", not ok)
ok, _ = run(f"insert into chat_messages(channel,body,from_user) values ('general','fake','{P}')", A2)
check("cannot post as someone else", not ok)

# --- revoke ---
run(f"update profiles set active=false where id='{A1}'", P)
check("revoked PA sees nothing", val("select count(*) from appointments", A1) == "0")
ok, _ = run("insert into chat_messages(channel,body) values ('general','still here?')", A1)
check("revoked PA cannot post", not ok)
ok, _ = run(f"update profiles set active=true where id='{A1}'", A2)
check("PA02 cannot restore accounts", val(f"select active from profiles where id='{A1}'", P) == "f")

run(f"update profiles set active=true where id='{A1}'", P)
check("principal restores PA", val("select count(*) from appointments", A1) == "3")

# --- admin tables ---
ok, _ = run(f"insert into permissions(user_id,module,level) values ('{A2}','payroll','edit')", A2)
check("PA02 cannot grant itself permissions", not ok)
check("audit insert as self only", not run(f"insert into audit_log(actor,action) values ('{P}','fake')", A2)[0])
check("PA cannot read audit of others", val("select count(*) from audit_log where actor<>auth.uid()", A2) == "0")

# --- storage ---
run("insert into documents(title,ws,scope,storage_key) values ('Passport','Personal Affairs','PERSONAL','docs/a/passport.pdf'),('Agreement','AGL Group','BUSINESS','docs/b/agree.pdf')", P)
run("insert into storage.objects(bucket_id,name) values ('pems-files','docs/a/passport.pdf'),('pems-files','docs/b/agree.pdf')")
check("PA can open only the business file", val("select count(*) from storage.objects", A1) == "1")
check("PA02 can open business file in its workspace", val("select count(*) from storage.objects", A2) == "1")
ok, _ = run("insert into storage.objects(bucket_id,name) values ('pems-files','docs/c/x.pdf')", A1)
check("PA (documents view) cannot upload", not ok)
ok, _ = run("insert into storage.objects(bucket_id,name) values ('pems-files','docs/c/x.pdf')", A2)
check("PA02 (documents edit) can upload", ok)

print(f"\n{'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
