const menu = document.querySelector('.menu-button');
const nav = document.querySelector('#site-nav');
if (menu && nav) {
  menu.addEventListener('click', () => {
    const open = menu.getAttribute('aria-expanded') !== 'true';
    menu.setAttribute('aria-expanded', String(open));
    menu.setAttribute('aria-label', open ? '收起导航' : '展开导航');
    nav.classList.toggle('open', open);
  });
  nav.querySelectorAll('a').forEach(a => a.addEventListener('click', () => {
    menu.setAttribute('aria-expanded', 'false'); menu.setAttribute('aria-label', '展开导航'); nav.classList.remove('open');
  }));
}
const modes = {
  preview: {title:'长一点，也能从容看。', description:'双指放大查看细节，上下浏览整张长图。先看清楚，再决定保留什么。', image:'assets/preview.webp', alt:'续页 App 中的长图示例预览，支持缩放和上下浏览', caption:'长图预览 · 实际 App 界面', items:['向上、向下都能扩展，回看已捕捉内容不重复加入。','固定背景与动态页面可能留下接缝，导出前请检查。']},
  crop: {title:'留下刚刚好的长度。', description:'调整起点和终点，把不需要的首尾裁掉。预览中直接看到保留的范围。', image:'assets/crop.webp', alt:'续页 App 编辑器的裁剪界面，可调整保留范围', caption:'裁剪起止 · 实际 App 界面', items:['通过滑块调整起止位置，随时还原。','编辑不会替你补齐缺失内容，先确认捕捉范围完整。']},
  redact: {title:'分享之前，遮住私密。', description:'圈选需要遮挡的位置，用不透明遮挡覆盖内容。导出时，遮挡会写进图片像素。', image:'assets/redact.webp', alt:'续页 App 中的不透明隐私遮挡示例', caption:'隐私遮挡 · 实际 App 界面', items:['姓名、号码或不想分享的片段，由你选择遮挡。','App 内原始画面仍保留以便重编，删除作品才会移除。']},
  export: {title:'保存一张，分享一整页。', description:'文字细节选 PNG，想减小文件选 JPEG。保存到照片，或通过系统分享交给你选择的 App。', image:'assets/export.webp', alt:'续页 App 的 PNG、JPEG 和保存到照片入口', caption:'保存与分享 · 实际 App 界面', items:['仅在保存时申请添加照片权限，不要求读取相册。','当前版本每周免费导出 50 个新作品，失败和重复导出不多计数。']}
};
const tabs = [...document.querySelectorAll('[data-mode]')];
const screen = document.querySelector('#feature-screen');
const dialog = document.querySelector('#screen-dialog');
const dialogImage = document.querySelector('#dialog-image');
function chooseMode(key, focus = false) {
  const entry = modes[key]; if (!entry || !screen) return;
  tabs.forEach(tab => { const selected = tab.dataset.mode === key; tab.setAttribute('aria-selected', String(selected)); tab.tabIndex = selected ? 0 : -1; if(selected && focus)tab.focus(); });
  screen.src = entry.image; screen.alt = entry.alt;
  document.querySelector('#feature-title').textContent = entry.title;
  document.querySelector('#feature-description').textContent = entry.description;
  document.querySelector('#feature-caption').textContent = entry.caption;
  const list = document.querySelector('#feature-points'); list.replaceChildren(...entry.items.map(t => { const li=document.createElement('li');li.textContent=t;return li;}));
  document.querySelector('#feature-panel').setAttribute('aria-labelledby', `mode-${key}`);
  if(dialogImage){dialogImage.src=entry.image;dialogImage.alt=entry.alt;document.querySelector('#dialog-title').textContent=entry.caption;}
}
tabs.forEach((tab,index)=>{
  tab.addEventListener('click',()=>chooseMode(tab.dataset.mode));
  tab.addEventListener('keydown',event=>{
    let next;
    if(event.key==='ArrowRight')next=(index+1)%tabs.length;
    if(event.key==='ArrowLeft')next=(index+tabs.length-1)%tabs.length;
    if(event.key==='Home')next=0;
    if(event.key==='End')next=tabs.length-1;
    if(next!==undefined){event.preventDefault();chooseMode(tabs[next].dataset.mode,true);}
  });
});
if(dialog){
  document.querySelectorAll('[data-enlarge]').forEach(button=>button.addEventListener('click',()=>dialog.showModal()));
  dialog.querySelector('[data-close]').addEventListener('click',()=>dialog.close());
  dialog.addEventListener('click',event=>{if(event.target===dialog)dialog.close();});
}
