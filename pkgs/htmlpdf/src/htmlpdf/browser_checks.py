"""Bounded browser readiness and source evidence used by PDF quality checks."""
WAIT_JS = r"""
async (timeout) => {
  let timer;
  const ready = async () => {
    for (const img of document.images) img.loading = 'eager';
    const step = Math.max(200, window.innerHeight * 0.8);
    const height = document.documentElement.scrollHeight;
    for (let y = 0, count = 0; y < height && count < 200; y += step, count++) {
      window.scrollTo(0, y);
      await new Promise(resolve => setTimeout(resolve, 15));
    }
    window.scrollTo(0, 0);
    await Promise.all([...document.images].map(img => img.complete ? null : new Promise(resolve => {
      img.addEventListener('load', resolve, { once:true });
      img.addEventListener('error', resolve, { once:true });
    })));
    if (window.MathJax?.startup?.promise) await window.MathJax.startup.promise;
    if (typeof window.MathJax?.typesetPromise === 'function') await window.MathJax.typesetPromise();
    await document.fonts.ready;
  };
  try {
    await Promise.race([ready(), new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('Timed out waiting for report images, fonts or MathJax')), timeout);
    })]);
  } finally { clearTimeout(timer); }
}
"""

SOURCE_CHECKS_JS = r"""
() => {
  const issues = [], expectedLinks = [], ids = new Set(), pairs = new Set();
  const visible = el => !!el.getClientRects().length && getComputedStyle(el).visibility !== 'hidden';
  const clean = value => (value || '').replace(/\s+/g, ' ').trim();
  for (const el of document.querySelectorAll('[id]')) {
    if (ids.has(el.id)) issues.push({code:'duplicate_anchor', severity:'error', page:null, message:`Duplicate anchor #${el.id}`});
    ids.add(el.id);
  }
  for (const link of document.querySelectorAll('a[href^="#"]')) {
    if (!visible(link) || link.getAttribute('href') === '#') continue;
    let id;
    try { id = decodeURIComponent(link.getAttribute('href').slice(1)); }
    catch { issues.push({code:'invalid_anchor', severity:'error', page:null, message:'Invalid encoded anchor'}); continue; }
    const target = document.getElementById(id) || document.getElementsByName(id)[0];
    if (!target) {
      issues.push({code:'missing_anchor', severity:'error', page:null, message:`Link ${clean(link.innerText)} has no target #${id}`});
      continue;
    }
    const targetNode = clean(target.textContent) ? target : target.parentElement;
    const text = clean(link.innerText);
    const heading = targetNode?.querySelector('h1,h2,h3,h4,b,strong');
    const fullTarget = clean(heading?.innerText || targetNode?.innerText);
    const targetText = fullTarget.length > 70 ? fullTarget.slice(0,70).replace(/\s+\S*$/, '') : fullTarget;
    const key = text + '\n' + id;
    if (text && targetText && !pairs.has(key)) {
      expectedLinks.push({text, target_text:targetText, target_id:id}); pairs.add(key);
    }
  }
  for (const img of document.images) {
    if (visible(img) && (!img.complete || img.naturalWidth === 0))
      issues.push({code:'missing_image', severity:'error', page:null, message:`Image failed to load: ${img.getAttribute('src') || '(empty source)'}`});
  }
  for (const el of document.querySelectorAll('table,pre,svg,img,canvas')) {
    if (!visible(el) || !el.parentElement) continue;
    const rect = el.getBoundingClientRect(), parent = el.parentElement.getBoundingClientRect();
    if (rect.right > parent.right + 2 || rect.left < parent.left - 2)
      issues.push({code:'horizontal_overflow', severity:'error', page:null, message:`${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''} exceeds its container by ${Math.round(Math.max(rect.right-parent.right,parent.left-rect.left))}px`});
  }
  return {issues, expectedLinks};
}
"""
