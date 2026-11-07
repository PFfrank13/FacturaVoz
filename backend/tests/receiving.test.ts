import {beforeEach,expect,it,vi} from 'vitest';
const m=vi.hoisted(()=>({context:vi.fn(),rpc:vi.fn(),from:vi.fn(),insert:vi.fn()}));
vi.mock('@/lib/erp/context',()=>({workspaceContext:m.context}));
vi.mock('next/cache',()=>({revalidatePath:vi.fn()}));
import {receiveStock} from '../src/app/erp/receiving';
import {createRecord} from '../src/app/erp/actions';
const id='11111111-1111-4111-8111-111111111111';
const input={requestId:id,supplier:'Proveedor QA',reference:'F001-QA',lines:[{product_id:id,quantity:5,unit_cost:6}]};
beforeEach(()=>{
 m.from.mockReturnValue({insert:m.insert});m.insert.mockReset();m.insert.mockResolvedValue({error:null});
 m.context.mockResolvedValue({db:{rpc:m.rpc,from:m.from},user:{id},sector:'bodega',access:{is_admin:true},license:{enforced:true,source:'hub',mode:'full',features:{stock:true,facturar:true}}});
 m.rpc.mockReset();m.rpc.mockResolvedValue({data:id,error:null});
});
it('uses one atomic receiving RPC with all lines and the same operation UUID',async()=>{
 expect(await receiveStock(id,input)).toMatchObject({ok:true,id});
 expect(m.rpc).toHaveBeenCalledExactlyOnceWith('retail_receive',{p_org:id,p_request:id,p_supplier:input.supplier,p_reference:input.reference,p_lines:input.lines});
});
it('does not send duplicates or invalid quantities',async()=>{
 expect(await receiveStock(id,{...input,lines:[input.lines[0],input.lines[0]]})).toMatchObject({ok:false,rejected:true});
 expect(await receiveStock(id,{...input,lines:[{...input.lines[0],quantity:0}]})).toMatchObject({ok:false,rejected:true});
 expect(m.rpc).not.toHaveBeenCalled();
});
it('distinguishes a known rollback from an unknown transport result',async()=>{
 m.rpc.mockResolvedValueOnce({error:{code:'23505'}}).mockResolvedValueOnce({error:{code:'network'}});
 expect(await receiveStock(id,input)).toMatchObject({ok:false,rejected:true});
 expect((await receiveStock(id,input)).rejected).toBeUndefined();
});
it('requires inventory and finance permissions before writing',async()=>{
 const context=await m.context();context.access={can:{finance:false}};
 expect(await receiveStock(id,input)).toMatchObject({ok:false,rejected:true});
 expect(m.rpc).not.toHaveBeenCalled();
});
it('creates a stock-tracked product at zero for subsequent receipt without publishing it',async()=>{
 const form=new FormData();form.set('name','Nuevo producto');form.set('unit_price','10');form.set('unit','NIU');form.set('track_stock','on');
 expect((await createRecord(id,'productos',{ok:false,message:''},form)).ok).toBe(true);
 expect(m.insert).toHaveBeenCalledWith(expect.objectContaining({org_id:id,user_id:id,stock:0,in_store:false}));
});
it('rejects a forged inventory switch without stock entitlement',async()=>{
 const c=await m.context();c.license.features.stock=false;
 const form=new FormData();form.set('name','Nuevo producto');form.set('unit_price','10');form.set('unit','NIU');form.set('track_stock','on');
 expect((await createRecord(id,'productos',{ok:false,message:''},form)).ok).toBe(false);
 expect(m.insert).not.toHaveBeenCalled();
});
