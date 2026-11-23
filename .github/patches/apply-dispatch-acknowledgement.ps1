$ErrorActionPreference = 'Stop'
$project = Join-Path $env:GITHUB_WORKSPACE 'NITRAM_TAURI_SQLITE_PROJECT'
$appPath = Join-Path $project 'dist/app.js'
$app = Get-Content -LiteralPath $appPath -Raw

# Cashier must be able to open Stock to import and acknowledge deliveries.
$roleOld = "Cashier:['sale','held','sales','expenses','shifts']"
$roleNew = "Cashier:['sale','held','sales','stock','expenses','shifts']"
if ($app.Contains($roleOld)) { $app = $app.Replace($roleOld,$roleNew) }
if (-not $app.Contains($roleNew)) { throw 'Cashier Stock access could not be enabled.' }

$start = $app.IndexOf('async function importStockDispatch(event)')
$end = $app.IndexOf('function stockRows(items)', $start)
if ($start -lt 0 -or $end -lt 0) { throw 'Dispatch import function boundaries were not found.' }

$replacement = @'
async function importStockDispatch(event){
 const file=event.target.files?.[0];if(!file)return;
 try{
  const data=JSON.parse(await file.text());
  if(data.schema==='NITRAM-STOCK-ACK'){
   const record=(S.stockDispatches||[]).find(x=>x.dispatchId===data.dispatchId);
   if(!record)throw new Error('No matching dispatch exists on this Owner database.');
   if(record.acknowledgement)throw new Error('This acknowledgement has already been imported.');
   record.acknowledgement=data;record.acknowledgedAt=data.acknowledgedAt;record.status=data.discrepancies?.length?'received-with-discrepancy':'received';
   logActivity('Cashier dispatch acknowledged',data.dispatchId+' · '+record.status);save();render('stock');toast('Cashier acknowledgement recorded.');return;
  }
  if(data.schema!=='NITRAM-STOCK-DISPATCH'||data.version!==1||!data.dispatchId||!Array.isArray(data.items)||!data.items.length)throw new Error('This is not a valid NITRAM dispatch file.');
  S.stockDispatches=S.stockDispatches||[];if(S.stockDispatches.some(x=>x.dispatchId===data.dispatchId))throw new Error('This dispatch has already been imported.');
  const prepared=data.items.map(x=>{const p=prod(String(x.productId));const q=Number(x.quantity);if(!p||!Number.isInteger(q)||q<=0)throw new Error('Invalid product or quantity in dispatch: '+(x.productId||''));return {p,q,item:x}});
  const lines=prepared.map(({p,q})=>'<label style="display:grid;grid-template-columns:1fr 90px;gap:10px;align-items:center;padding:9px 0;border-bottom:1px solid #eee"><span><b>'+escapeScanHtml(p.name)+'</b><small style="display:block;color:#667085">Sent: '+q+'</small></span><input type=number min=0 max='+q+' step=1 value='+q+' data-received-product="'+escapeScanHtml(p.id)+'" data-sent-qty="'+q+'" style="width:100%"></label>').join('');
  window.pendingStockDispatch=data;
  document.getElementById('modal').style.display='grid';
  document.getElementById('modal').innerHTML='<div class="modalbox" style="max-width:680px;max-height:88vh;overflow:auto"><h2>Verify stock received</h2><p class=muted>Dispatch '+escapeScanHtml(data.dispatchId)+' from '+escapeScanHtml(data.sender||'Owner')+'. Check each quantity physically. Reduce the received quantity for shortages or damaged goods.</p>'+lines+'<div class=pay-actions><button class=ghost onclick="closeModal()">Cancel</button><button class=btn onclick="confirmStockDispatchReceipt()">Confirm receipt & export acknowledgement</button></div></div>';
 }catch(err){toast(err.message||'Could not import dispatch. No stock was changed.')}
 finally{event.target.value=''}
}
function confirmStockDispatchReceipt(){
 const data=window.pendingStockDispatch;if(!data)return toast('No pending dispatch to receive');
 const inputs=[...document.querySelectorAll('[data-received-product]')],accepted=[],discrepancies=[];
 for(const el of inputs){const sent=Number(el.dataset.sentQty),received=Number(el.value),p=prod(el.dataset.receivedProduct);if(!p||!Number.isInteger(received)||received<0||received>sent)return toast('Received quantities must be whole numbers between zero and sent quantity');accepted.push({productId:p.id,name:p.name,sent,received});if(received!==sent)discrepancies.push({productId:p.id,name:p.name,sent,received,shortage:sent-received})}
 if(!accepted.length)return toast('No dispatch lines found');
 accepted.forEach(x=>{const p=prod(x.productId);p.stock=Number(p.stock||0)+x.received});
 const ack={schema:'NITRAM-STOCK-ACK',version:1,dispatchId:data.dispatchId,sender:data.sender||'Owner',receiver:S.currentUser?.name||'Cashier',receivedAt:new Date().toISOString(),acknowledgedAt:new Date().toISOString(),discrepancies,items:accepted};
 S.stockDispatches=S.stockDispatches||[];S.stockDispatches.unshift({dispatchId:data.dispatchId,sender:data.sender||'Owner',receiver:data.receiver||'',createdAt:data.createdAt||'',acknowledgedAt:ack.acknowledgedAt,status:discrepancies.length?'received-with-discrepancy':'received',role:'receiver',items:data.items.map(x=>({...x})),acknowledgement:ack});
 logActivity('Stock dispatch received',data.dispatchId+' · '+accepted.map(x=>x.name+' '+x.received+'/'+x.sent).join('; '));save();
 const blob=new Blob([JSON.stringify(ack,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=data.dispatchId+'.ack.nitram.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1500);
 window.pendingStockDispatch=null;closeModal();render('stock');toast(discrepancies.length?'Receipt saved with discrepancies. Send acknowledgement to Owner.':'Receipt confirmed. Send acknowledgement to Owner.');
}
'@
$app = $app.Substring(0,$start) + $replacement + [Environment]::NewLine + $app.Substring($end)
Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8
node --check $appPath
if ($LASTEXITCODE -ne 0) { throw 'JavaScript syntax check failed after acknowledgement patch.' }
Write-Host 'Added cashier access, verified receipt quantities, discrepancy records and Owner acknowledgement import.'
