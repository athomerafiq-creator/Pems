// In-memory stand-in for supabase-js, used only by the browser smoke test.
// It does NOT enforce security (that is tested against PostgreSQL in rls_test.py).
(function(){
const uid=()=>([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g,c=>(c^crypto.getRandomValues(new Uint8Array(1))[0]&15>>c/4).toString(16));
const P='00000000-0000-0000-0000-00000000000p'.replace('p','1'),A1='00000000-0000-0000-0000-000000000002',A2='00000000-0000-0000-0000-000000000003';
const ME={p:P,a1:A1,a2:A2}[window.MOCK_USER||'p'];
const now=()=>new Date().toISOString();const today=new Date().toISOString().slice(0,10);
const DB={
 profiles:[{id:P,email:'athomerafiq@gmail.com',name:'M Rafiq Hoque',title:'Principal',role:'principal',active:true,color:'#b45309',created_at:'2026-01-01'},
  {id:A1,email:'pstocoo.ishc@gmail.com',name:'Md Sumon Reza',title:'Executive Assistant (PA)',role:'assistant',active:true,color:'#be185d',created_at:'2026-01-02'},
  {id:A2,email:'support@revenuehelper.org',name:'PA02',title:'Administrative Assistant (PA02)',role:'assistant',active:true,color:'#0e7490',created_at:'2026-01-03'}],
 workspaces:['Big7Placements','AGL Group','Consulting & Partnerships','Personal Affairs'].map((n,i)=>({id:uid(),name:n,color:['#2f6bff','#22c55e','#8b5cf6','#f59e0b'][i],created_at:'2026-01-0'+(i+1)})),
 permissions:[],workspace_access:[{user_id:A1,workspace:'AGL Group'},{user_id:A1,workspace:'Big7Placements'},{user_id:A2,workspace:'AGL Group'}],
 app_settings:[{id:1,data:{view:'BDT',rate:123,late:'09:30',tz:'Asia/Dhaka',notify:{on:true,email:'athomerafiq@gmail.com',cal:true,calEmail:'athomerafiq@gmail.com',ev:{approvals:true,tasks:true,meetings:true,warnings:true,reports:true,payroll:true}}}}],
 appointments:[{id:uid(),title:'Strategy meeting',date:today,start_time:'09:00',end_time:'10:00',location:'Office',ws:'AGL Group',scope:'BUSINESS',gcal:true,archived:false,created_by:P,created_at:now()}],
 tasks:[{id:uid(),title:'Board pack',status:'Review',priority:'High',due:today,assignee:A1,ws:'AGL Group',scope:'BUSINESS',archived:false,created_by:P,created_at:now()}],
 contacts:[{id:uid(),name:'Nadia Rahman',company:'Big7',reference:'Conference',whatsapp:'+8801811222333',email:'n@example.com',ws:'Big7Placements',scope:'BUSINESS',archived:false,created_by:P,created_at:now()}],
 documents:[{id:uid(),title:'Licence',category:'Professional',confidentiality:'Normal',file_name:'l.pdf',file_size:'10 KB',storage_key:'docs/x/l.pdf',version:1,ws:'AGL Group',scope:'BUSINESS',archived:false,created_by:P,created_at:now()}],
 meetings:[],travel:[],
 transactions:[{id:uid(),date:today,type:'Income',category:'Salary',amount:5000,currency:'USD',ws:'Big7Placements',status:'Approved',archived:false,created_by:P,created_at:now()},{id:uid(),date:today,type:'Expense',category:'Courier',amount:1200,currency:'BDT',ws:'AGL Group',status:'Pending',archived:false,created_by:A2,created_at:now()}],
 staff:[{id:'s1',name:'Md Sumon Reza',role:'PA',salary:60000,currency:'BDT',user_id:A1,archived:false,created_at:now()},{id:'s2',name:'PA02',role:'PA02',salary:45000,currency:'BDT',user_id:A2,archived:false,created_at:now()}],
 payroll_adjustments:[{id:uid(),staff_id:'s1',month:today.slice(0,7),type:'Incentive',amount:5000,currency:'BDT',archived:false,created_at:now()}],
 attendance:[{id:uid(),user_id:A1,date:today,check_in:'09:05',check_out:null,archived:false,created_at:now()}],
 warnings:[{id:uid(),staff_id:'s2',grade:'Grade 1',action:'Written warning',date:today,reason:'Late',acknowledged:null,archived:false,created_at:now()}],
 chat_messages:[{id:uid(),channel:'general',from_user:P,body:'Hello team',created_at:now()}],
 chat_seen:[],focus_items:[{id:uid(),text:'Review correspondence',done:false,created_at:now()}],
 audit_log:[],email_outbox:[],report_runs:[],payroll_runs:[]
};
['calendar','tasks','contacts','documents','meetings','chat','attendance','warnings','travel','reports','dashboard'].forEach(m=>{DB.permissions.push({user_id:A1,module:m,level:m==='attendance'||m==='warnings'||m==='reports'||m==='dashboard'?'view':'edit'})});
['tasks','chat','documents','finance','attendance','warnings','reports','dashboard'].forEach(m=>{DB.permissions.push({user_id:A2,module:m,level:m==='finance'?'entry':(m==='tasks'||m==='chat'||m==='documents')?'edit':'view'})});
window.__MOCKDB=DB;
function Q(t){this.t=t;this.op='select';this.f=[];this.ord=null;this.lim=null;this.ret=false}
Q.prototype.select=function(){if(this.op==='select')this.op='select';this.ret=true;return this};
Q.prototype.order=function(c,o){this.ord=[c,(o&&o.ascending===false)?-1:1];return this};
Q.prototype.limit=function(n){this.lim=n;return this};
Q.prototype.eq=function(c,v){this.f.push(r=>r[c]===v);return this};
Q.prototype.neq=function(c,v){this.f.push(r=>r[c]!==v);return this};
Q.prototype.not=function(){return this};
Q.prototype.insert=function(rows){this.op='insert';this.rows=[].concat(rows);return this};
Q.prototype.upsert=function(rows,o){this.op='upsert';this.rows=[].concat(rows);this.oc=(o&&o.onConflict)||'id';return this};
Q.prototype.update=function(p){this.op='update';this.patch=p;return this};
Q.prototype.delete=function(){this.op='delete';return this};
Q.prototype.then=function(res,rej){try{res(this.exec())}catch(e){rej?rej(e):res({data:null,error:e})}};
Q.prototype.exec=function(){const T=DB[this.t]||(DB[this.t]=[]);const match=r=>this.f.every(f=>f(r));
 if(this.op==='select'){let d=T.filter(match);if(this.ord){const[c,s]=this.ord;d=d.slice().sort((a,b)=>String(a[c]).localeCompare(String(b[c]))*s)}if(this.lim)d=d.slice(0,this.lim);return {data:JSON.parse(JSON.stringify(d)),error:null}}
 if(this.op==='insert'){const out=this.rows.map(r=>{const x=Object.assign({id:uid(),created_at:now(),archived:false},r);if(!('created_by' in x))x.created_by=ME;if(this.t==='transactions'&&ME!==P)x.status='Pending';if(this.t==='attendance'&&!x.check_out)x.check_out=null;T.push(x);return x});return {data:out,error:null}}
 if(this.op==='upsert'){const out=this.rows.map(r=>{const k=this.oc.split(',');const e=T.find(x=>k.every(c=>x[c]===r[c]));if(e){Object.assign(e,r);return e}const x=Object.assign({id:uid(),created_at:now()},r);T.push(x);return x});return {data:out,error:null}}
 if(this.op==='update'){const d=T.filter(match);d.forEach(r=>Object.assign(r,this.patch));return {data:d,error:null}}
 if(this.op==='delete'){const d=T.filter(match);DB[this.t]=T.filter(r=>!match(r));return {data:d,error:null}}
};
window.supabase={createClient(){return {
 from:t=>new Q(t),
 rpc:(n,a)=>{if(n==='ack_warning'){const w=DB.warnings.find(x=>x.id===a.wid);if(w)w.acknowledged=today}return Promise.resolve({data:null,error:null})},
 storage:{from:()=>({upload:async(k)=>({data:{path:k},error:null}),createSignedUrl:async()=>({data:{signedUrl:'about:blank'},error:null})})},
 auth:{getSession:async()=>({data:{session:window.MOCK_NOAUTH?null:{user:{id:ME}}}}),onAuthStateChange(){return {data:{subscription:{unsubscribe(){}}}}},signOut:async()=>({}),
  signInWithPassword:async()=>({data:{session:{user:{id:ME}}},error:null}),updateUser:async()=>({data:{},error:null}),resetPasswordForEmail:async()=>({error:null})},
 channel(){const c={on(){return c},subscribe(){return c}};return c}
}}};
})();
