// Local-only UI -> PostgreSQL harness. Uses only a fixed synthetic tenant;
// never accepts connection URLs, arbitrary SQL, user IDs or organization IDs.
import { createServer } from 'vite';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { z } from 'zod';
const database=process.argv[2];
if(!/^retail_restore_\d+$/.test(database ?? '')) throw Error('Use a successful isolated POS clone');
const container='solvex-cloud-lab-20261107';
const user='11111111-1111-4111-8111-111111111111';
const root=fileURLToPath(new URL('../',import.meta.url));
const qa=path.join(root,'tests/retail-lab');
const run=(args,input='')=>new Promise((resolve,reject)=>{
 const child=spawn('docker',args);let out='';let err='';
 child.stdout.on('data',b=>out+=b);child.stderr.on('data',b=>err+=b);
 child.on('error',reject);child.on('close',code=>code?reject(Error(err)):resolve(out.trim()));
 child.stdin.end(input);
});
if(await run(['inspect','--format','{{.HostConfig.NetworkMode}}|{{len .Mounts}}',container])!=='none|0') throw Error('Isolation required');
const args=['exec','-i',container,'psql','-h','/tmp','-U','postgres','-d',database,'-qAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'];
const session=`SET ROLE authenticated; SET request.jwt.claim.sub='${user}';`;
const org=`(select org_id from public.organization_members where user_id=auth.uid() limit 1)`;
const query=sql=>run(args,session+sql);
const sale=z.object({requestId:z.uuid(),currency:z.literal('PEN'),taxBasisPoints:z.literal(1800),method:z.enum(['efectivo','yape','plin','tarjeta','transferencia']),items:z.array(z.object({product_id:z.uuid(),quantity:z.number().positive().max(100000),unit_price:z.number().nonnegative().max(10000000)})).min(1).max(50)});
const server=await createServer({configFile:false,root:qa,
 server:{host:'127.0.0.1',port:3102,strictPort:true,fs:{allow:[root]}},
 resolve:{alias:[{find:'@/app/erp/checkout',replacement:path.join(qa,'checkout.ts')},{find:'next/link',replacement:path.join(root,'tests/retail-preview/link.tsx')},{find:'@',replacement:path.join(root,'src')}]},
 esbuild:{jsx:'automatic'},css:{postcss:{plugins:[]}},
 plugins:[{name:'isolated-retail-api',configureServer(vite){vite.middlewares.use(async(req,res,next)=>{
  if(!req.url?.startsWith('/__lab/')) return next();
  res.setHeader('Content-Type','application/json');res.setHeader('Cache-Control','no-store');
  if(req.headers.host!=='127.0.0.1:3102' || (req.headers.origin && req.headers.origin!=='http://127.0.0.1:3102')) {res.statusCode=403;return res.end('{}');}
  try {
   if(req.method==='GET' && req.url==='/__lab/state') {
    return res.end(await query(`select json_build_object('user','${user}','org',${org},
     'products',(select coalesce(json_agg(t),'[]') from(select id,name,unit_price,stock from public.products where org_id=${org} and active order by name)t),
     'history',(select coalesce(json_agg(t),'[]') from(select id,number,status,amt_total from public.invoices where org_id=${org} order by created_at desc)t),
     'cash',public.day_summary(${org},(now() at time zone 'America/Lima')::date));`));
   }
   if(req.method!=='POST'||req.url!=='/__lab/checkout'||!req.headers['content-type']?.startsWith('application/json')) {res.statusCode=405;return res.end('{}');}
   let body='';for await(const chunk of req){body+=chunk;if(body.length>64000)throw Error('Too large');}
   const input=sale.parse(JSON.parse(body));
   const hex=Buffer.from(JSON.stringify(input.items.map(i=>({...i,description:'Venta de laboratorio'})))).toString('hex');
   const result=JSON.parse(await query(`select row_to_json(t) from public.fast_checkout_atomic(${org},'${input.requestId}',convert_from(decode('${hex}','hex'),'UTF8')::jsonb,18,'PEN','${input.method}')t;`));
   res.end(JSON.stringify({ok:true,message:'Venta persistida en PostgreSQL aislado.',invoiceId:result.invoice_id,charged:Number(result.charged)}));
  } catch (error) {
   const rejected=String(error).includes('P2001:');
   res.statusCode=400;res.end(JSON.stringify({ok:false,uncertain:!rejected,message:rejected?'Ticket rechazado sin venta. Revisa precios y cantidades.':'Operación sin confirmar. Reintenta el mismo identificador; revisa catálogo y stock.'}));
  }
 });}}]});
await server.listen();server.printUrls();
console.log('Synthetic session only. No hosted Auth, external payments, or production writes.');
