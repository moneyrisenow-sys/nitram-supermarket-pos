$ErrorActionPreference = 'Stop'
$project = Join-Path $env:GITHUB_WORKSPACE 'NITRAM_TAURI_SQLITE_PROJECT'
$appPath = Join-Path $project 'dist/app.js'
$app = Get-Content -LiteralPath $appPath -Raw

# Replace the catalogue-wide/manual dispatch control with one action that dispatches
# only unallocated quantities recorded by stock-receive movements.
$oldButton = '<button class=btn onclick="openStockDispatch()">Send Stock to Cashier</button>'
$newButton = '<button class=btn onclick="dispatchNewlyReceivedStock()">Dispatch Newly Received</button>'
if ($app.Contains($oldButton)) {
  $app = $app.Replace($oldButton,$newButton)
} elseif (-not $app.Contains('onclick="dispatchNewlyReceivedStock()"')) {
  throw 'Could not locate the existing stock dispatch control; refusing to patch an unknown Stock UI.'
}

$code = @'
function _nitramReceiveLedger(){
 const candidates=[S.stockAdjustments,S.stockMovements,S.stockHistory,S.movements,S.stockTransactions,S.inventoryMovements];
 for(const list of candidates){if(Array.isArray(list)&&list.length)return list}
 return [];
}
function _nitramReceiveField(m,keys){for(const k of keys){if(m&&m[k]!==undefined&&m[k]!==null&&m[k]!=='')return m[k]}return null}
function _nitramReceiveKey(m,index){
 const explicit=_nitramReceiveField(m,['movementId','transactionId','receiptId','id','uid','ref','reference']);
 if(explicit!==null)return String(explicit);
 const stamp=_nitramReceiveField(m,['createdAt','timestamp','date','time','created_at'])||'';
 const pid=_nitramReceiveField(m,['productId','product_id','product','idProduct','itemId','barcode'])||'';
 const qty=_nitramReceiveField(m,['delta','quantity','qty','amount','units','change','quantityIn'])||'';
 return 'receive-'+String(stamp)+'-'+String(pid)+'-'+String(qty)+'-'+index;
}
function _nitramReceivedMovements(){
 const ledger=_nitramReceiveLedger(),alloc=S.stockDispatchAllocations||(S.stockDispatchAllocations={}),out=[];
 ledger.forEach((m,i)=>{
  const type=String(_nitramReceiveField(m,['type','action','movementType','transactionType','kind','operation','reason'])||'').toLowerCase();
  if(!/(receive|received|goods in|stock in|purchase|supplier receipt)/.test(type))return;
  if(m&&m.delta!==undefined&&Number(m.delta)<=0)return;
  const productId=String(_nitramReceiveField(m,['productId','product_id','product','idProduct','itemId','barcode'])||'');
  const rawQty=_nitramReceiveField(m,['delta','quantity','qty','amount','units','quantityIn','receivedQty']);
  const qty=Math.abs(Number(rawQty));
  if(!productId||!Number.isFinite(qty)||qty<=0)return;
  const p=prod(productId)||((S.products||[]).find(x=>String(x.barcode||'')===productId));
  if(!p)return;
  const key=_nitramReceiveKey(m,i),already=Math.max(0,Number(alloc[key]||0));
  const available=Math.max(0,Math.min(qty-already,Number(p.stock||0)));
  if(available>0)out.push({key,productId:p.id,name:p.name,barcode:p.barcode||p.id,quantity:available,sourceQuantity:qty});
 });
 return out;
}
function dispatchNewlyReceivedStock(){
 if(S.activeRole!=='Owner')return toast('Only the Owner can dispatch stock');
 const eligible=_nitramReceivedMovements();
 if(!eligible.length)return toast('No undispatched quantities from stock receipts are available.');
 const items=eligible.map(x=>({productId:x.productId,name:x.name,barcode:x.barcode,quantity:x.quantity,receiptKey:x.key}));
 const receiver=String(S.dispatchReceiver||S.defaultCashier||'Cashier').trim()||'Cashier';
 const dispatch={schema:'NITRAM-STOCK-DISPATCH',version:1,dispatchId:'DSP-'+Date.now()+'-'+Math.random().toString(36).slice(2,8).toUpperCase(),sender:S.currentUser?.name||'Owner',receiver,createdAt:new Date().toISOString(),status:'sent',source:'newly-received-stock',items};
 // Validate the complete dispatch before changing any stock or allocation.
 for(const item of items){const p=prod(item.productId);if(!p||!Number.isInteger(item.quantity)||item.quantity<=0||item.quantity>Number(p.stock||0))return toast('Stock changed while preparing dispatch. Refresh and try again.')}
 const allocations=S.stockDispatchAllocations||(S.stockDispatchAllocations={});
 items.forEach(item=>{const p=prod(item.productId);p.stock=Number(p.stock||0)-item.quantity;allocations[item.receiptKey]=Number(allocations[item.receiptKey]||0)+item.quantity});
 S.stockDispatches=S.stockDispatches||[];S.stockDispatches.unshift({...dispatch,role:'sender',acknowledgedAt:null});
 logActivity('Newly received stock dispatched',dispatch.dispatchId+' · to '+receiver+' · '+items.map(x=>x.name+' × '+x.quantity).join('; '));
 save();
 const blob=new Blob([JSON.stringify(dispatch,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');
 a.href=url;a.download=dispatch.dispatchId+'.nitram-dispatch.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1500);
 render('stock');toast('Newly received stock dispatched. Send the downloaded file to the cashier.');
}
'@

if (-not $app.Contains('function dispatchNewlyReceivedStock()')) {
  $marker = 'function stockRows(items)'
  if (-not $app.Contains($marker)) { throw 'Stock rendering insertion point missing; refusing to patch.' }
  $app = $app.Replace($marker,$code+[Environment]::NewLine+$marker)
}

Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8
node --check $appPath
if ($LASTEXITCODE -ne 0) { throw 'JavaScript syntax validation failed after received-stock dispatch patch.' }
Write-Host 'Applied one-click dispatch of unallocated received-stock movement quantities.'
