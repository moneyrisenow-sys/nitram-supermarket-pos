$ErrorActionPreference = 'Stop'
$project = Join-Path $env:GITHUB_WORKSPACE 'NITRAM_TAURI_SQLITE_PROJECT'
$appPath = Join-Path $project 'dist/app.js'
$app = Get-Content -LiteralPath $appPath -Raw
$needle = 'S.stockAdjustments=Array.isArray(S.stockAdjustments)?S.stockAdjustments:[];'
if ($app.Contains($needle) -and -not $app.Contains('S.stockDispatches=Array.isArray')) { $app = $app.Replace($needle,$needle + [Environment]::NewLine + 'S.stockDispatches=Array.isArray(S.stockDispatches)?S.stockDispatches:[];') }
$old = '<button class=btn onclick="openStockAdjustment()">Adjust Stock</button>'
$new = '<div style="display:flex;gap:8px;flex-wrap:wrap"><button class=ghost onclick="openStockDispatchImport()">Import Dispatch</button><button class=btn onclick="openStockDispatch()">Send Stock to Cashier</button><button class=ghost onclick="openStockAdjustment()">Adjust Stock</button><input id="stockDispatchFile" type="file" accept=".json,application/json" style="display:none" onchange="importStockDispatch(event)"></div>'
if ($app.Contains($old) -and -not $app.Contains('openStockDispatchImport()')) { $app = $app.Replace($old,$new) }
$marker = 'function stockRows(items)'
$code = @'
function openStockDispatchImport(){document.getElementById('stockDispatchFile')?.click()}
function openStockDispatch(){
 if(S.activeRole!=='Owner')return toast('Only the Owner can dispatch stock');
 const rows=(S.products||[]).filter(p=>Number(p.stock)>0).map(p=>'<label style="display:grid;grid-template-columns:1fr 100px;gap:10px;align-items:center;padding:8px 0;border-bottom:1px solid #eee"><span><b>'+escapeScanHtml(p.name)+'</b><small class="muted" style="display:block">'+escapeScanHtml(p.id)+' · Available '+(Number(p.stock)||0)+'</small></span><input data-dispatch-product="'+escapeScanHtml(p.id)+'" type="number" min="0" max="'+(Number(p.stock)||0)+'" step="1" value="0" style="width:100%"></label>').join('');
 document.getElementById('modal').style.display='grid';
 document.getElementById('modal').innerHTML='<div class="modalbox" style="max-width:760px;max-height:88vh;overflow:auto"><h2>Send stock to cashier</h2><p class="muted">Create an offline dispatch file. Stock is deducted from the office immediately; the cashier imports the file to receive it. Each dispatch can only be imported once.</p><label>Cashier / destination<input id="dispatchReceiver" placeholder="Cashier name or Till 1" required></label><div style="margin-top:12px">'+(rows||'<p>No stock available to dispatch.</p>')+'</div><div class="pay-actions"><button class="ghost" onclick="closeModal()">Cancel</button><button class="btn" onclick="createStockDispatch()">Create dispatch file</button></div></div>';
}
function createStockDispatch(){
 const receiver=(document.getElementById('dispatchReceiver')?.value||'').trim();if(!receiver)return toast('Enter the cashier or destination');
 const inputs=[...document.querySelectorAll('[data-dispatch-product]')],items=[];
 for(const el of inputs){const qty=Number(el.value),p=prod(el.dataset.dispatchProduct);if(!Number.isInteger(qty)||qty<0)return toast('Dispatch quantities must be whole numbers');if(qty>0){if(!p||qty>Number(p.stock))return toast('Insufficient stock for '+(p?.name||el.dataset.dispatchProduct));items.push({productId:p.id,name:p.name,barcode:p.barcode||p.id,quantity:qty})}}
 if(!items.length)return toast('Enter at least one dispatch quantity');
 const dispatch={schema:'NITRAM-STOCK-DISPATCH',version:1,dispatchId:'DSP-'+Date.now()+'-'+Math.random().toString(36).slice(2,8).toUpperCase(),sender:S.currentUser?.name||'Owner',receiver,createdAt:new Date().toISOString(),status:'sent',items};
 for(const item of items){const p=prod(item.productId);p.stock=Number(p.stock)-item.quantity}
 S.stockDispatches=S.stockDispatches||[];S.stockDispatches.unshift({...dispatch,role:'sender',acknowledgedAt:null});
 logActivity('Stock dispatched',dispatch.dispatchId+' · to '+receiver+' · '+items.map(x=>x.name+' × '+x.quantity).join('; '));save();
 const blob=new Blob([JSON.stringify(dispatch,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=dispatch.dispatchId+'.nitram-dispatch.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1500);
 closeModal();render('stock');toast('Dispatch created. Send the downloaded file to the cashier.');
}
async function importStockDispatch(event){
 const file=event.target.files?.[0];if(!file)return;
 try{
  const data=JSON.parse(await file.text());if(data.schema!=='NITRAM-STOCK-DISPATCH'||data.version!==1||!data.dispatchId||!Array.isArray(data.items)||!data.items.length)throw new Error('This is not a valid NITRAM dispatch file.');
  S.stockDispatches=S.stockDispatches||[];if(S.stockDispatches.some(x=>x.dispatchId===data.dispatchId))throw new Error('This dispatch has already been imported.');
  const prepared=data.items.map(x=>{const p=prod(x.productId);const q=Number(x.quantity);if(!p||!Number.isInteger(q)||q<=0)throw new Error('Invalid product or quantity in dispatch: '+(x.productId||''));return {p,q}});
  prepared.forEach(({p,q})=>{p.stock=Number(p.stock||0)+q});
  S.stockDispatches.unshift({dispatchId:data.dispatchId,sender:data.sender||'Unknown',receiver:data.receiver||'',createdAt:data.createdAt||'',acknowledgedAt:new Date().toISOString(),status:'received',role:'receiver',items:data.items.map(x=>({...x}))});
  logActivity('Stock dispatch received',data.dispatchId+' · from '+(data.sender||'Unknown')+' · '+data.items.map(x=>x.name+' × '+x.quantity).join('; '));save();render('stock');toast('Dispatch received and stock updated.');
 }catch(err){toast(err.message||'Could not import dispatch. No stock was changed.')}
 finally{event.target.value=''}
}
'@
if (-not $app.Contains('function createStockDispatch()')) { if (-not $app.Contains($marker)) { throw 'Stock table insertion point missing; aborting patch.' }; $app=$app.Replace($marker,$code+[Environment]::NewLine+$marker) }
$app = $app.Replace('variance=counted+expenses-expected,mpesaVariance=mpesaCounted-mpesaSales','variance=mpesaCounted+counted+expenses-netSales,mpesaVariance=mpesaCounted-mpesaSales')
$app = $app.Replace('money(counted+expense-expected)','money(mpesaCounted+counted+expense-sales.reduce((n,x)=>n+net(x),0))')
$app = $app.Replace('expectedCash:expected,countedCash:counted','expectedCash:counted,countedCash:counted')
Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8
Write-Host 'Applied offline stock dispatch and requested reconciliation formula.'
