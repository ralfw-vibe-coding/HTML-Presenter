// HTML-Presenter-Laufzeit für Schema-Version 1 (siehe SCHEMA.md).
// Darf mehrfach geladen werden: Die erste Kopie gewinnt (z. B. die von der App eingefügte).
(() => {
  if (window.presentation) return;

  const root = document.documentElement;
  const bridge = window.webkit?.messageHandlers?.presenter;
  const notify = message => { try { bridge?.postMessage(message); } catch {} };
  const mode = root.dataset.presentationMode ||= 'browser';

  const BASE_CSS = `@layer presentation {
    html, body { margin: 0; height: 100%; overflow: hidden; background: var(--presentation-backdrop, #000); }
    [data-slide] { position: fixed; inset: 0; box-sizing: border-box; overflow: hidden; }
    html[data-presentation-size] [data-slide] {
      inset: auto; left: 50%; top: 50%;
      width: var(--presentation-width); height: var(--presentation-height);
      transform: translate(-50%, -50%) scale(var(--presentation-scale, 1));
    }
    [data-slide]:not([data-state="current"]) { visibility: hidden; pointer-events: none; }
    [data-slide] [data-step]:not([data-step-shown]) { opacity: 0; pointer-events: none; }
    [data-notes] { display: none !important; }
    html[data-presentation-mode="snapshot"] *, html[data-presentation-mode="snapshot"] *::before, html[data-presentation-mode="snapshot"] *::after {
      transition: none !important; animation-duration: 0s !important; animation-delay: 0s !important;
    }
  }`;

  let slides = [];
  let current = -1;
  let step = 0;
  let size = null;
  let resolveReady;

  const api = window.presentation = {
    version: 1,
    mode,
    /** Hört hier jemand zu? Im Pult und bei Miniaturen bleibt es still. */
    audible: mode === 'browser' || mode === 'beamer',
    get size() { return size; },
    get slides() { return slides.map(({ element, ...rest }) => rest); },
    get current() { return current; },
    get step() { return step; },
    goto: (ref, toStep = 0) => show(resolve(ref), toStep),
    next: () => step < (slides[current]?.steps ?? 0) ? show(current, step + 1) : show(current + 1, 0),
    prev: () => step > 0 ? show(current, step - 1) : show(current - 1, Infinity),
    nextSection: () => show(slides.findIndex((s, k) => k > current && s.level === 1)),
    prevSection: () => {
      const here = slides[current];
      if (!here) return false;
      if (here.level > 1) return show(sectionOf(current));
      for (let k = current - 1; k >= 0; k--) if (slides[k].level === 1) return show(k);
      return false;
    },
    /** Löst eine Aktion aus, die überall laufen soll – hier und in den anderen Fenstern der App. */
    act: (name, detail = null) => {
      emit(document, 'presentation:action', { name, detail, remote: false });
      notify({ type: 'action', name, detail });
    },
    /** Von der App aufgerufen, wenn ein anderes Fenster eine Aktion ausgelöst hat. */
    receiveAction: (name, detail = null) => {
      emit(document, 'presentation:action', { name, detail, remote: true });
      return true;
    },
    ready: new Promise(r => { resolveReady = r; })
  };

  function sectionOf(index) {
    let k = index;
    while (slides[k].parent !== null) k = slides[k].parent;
    return k;
  }

  function resolve(ref) {
    if (typeof ref === 'number') return ref;
    if (ref instanceof Element) return slides.findIndex(s => s.element === ref || s.element.contains(ref));
    const text = String(ref).replace(/^#/, '');
    const byNumber = slides.findIndex(s => s.number === text);
    return byNumber >= 0 ? byNumber : slides.findIndex(s => s.id === text);
  }

  /** Überschrift als lesbarer Titel: Zeilenumbrüche werden Leerzeichen, weiche Trennstriche fallen weg. */
  function headingText(heading) {
    if (!heading) return '';
    const copy = heading.cloneNode(true);
    copy.querySelectorAll('br').forEach(br => br.replaceWith(' '));
    return copy.textContent.replace(/­/g, '');
  }

  function readSlides() {
    const counters = [];
    const lastAtLevel = [];
    return [...document.querySelectorAll('[data-slide]')].map((element, index) => {
      const previousLevel = index ? counters.length : 0;
      const level = Math.min(Math.max(1, parseInt(element.dataset.level, 10) || 1), previousLevel + 1);
      counters.length = level;
      counters[level - 1] = (counters[level - 1] || 0) + 1;
      lastAtLevel.length = level;
      lastAtLevel[level - 1] = index;
      const number = counters.join('.');
      element.dataset.slideNumber = number;
      const steps = Math.max(parseInt(element.dataset.steps, 10) || 0,
        ...[...element.querySelectorAll('[data-step]')].map(el => parseInt(el.dataset.step, 10) || 0));
      return {
        element,
        index,
        number,
        level,
        id: element.id || element.dataset.id || number,
        title: (element.dataset.title || headingText(element.querySelector('h1, h2, h3, h4, h5, h6'))).replace(/\s+/g, ' ').trim(),
        notes: [...element.querySelectorAll('[data-notes]')].map(n => n.innerHTML.trim()).join('\n'),
        steps,
        parent: level > 1 ? lastAtLevel[level - 2] : null,
        children: []
      };
    });
  }

  function readSize() {
    const meta = document.querySelector('meta[name="presentation"]')?.content || '';
    const width = parseFloat(meta.match(/width\s*=\s*([\d.]+)/)?.[1]);
    const height = parseFloat(meta.match(/height\s*=\s*([\d.]+)/)?.[1]);
    return width > 0 && height > 0 ? { width, height } : null;
  }

  function fit() {
    if (size) root.style.setProperty('--presentation-scale', Math.min(innerWidth / size.width, innerHeight / size.height));
  }

  function emit(target, name, detail) {
    target.dispatchEvent(new CustomEvent(name, { bubbles: true, detail }));
  }

  /** Zeigt Folie `index` mit `toStep` eingeblendeten Schritten (Infinity = alle). */
  function show(index, toStep = 0) {
    if (!Number.isInteger(index) || index < 0 || index >= slides.length) return false;
    const target = Math.min(Math.max(0, toStep), slides[index].steps);
    if (index === current && target === step) return true;

    const entering = index !== current;
    const previous = current;
    const previousStep = entering ? null : step;
    current = index;
    step = target;
    const outline = api.slides;
    const slide = outline[index];
    const element = slides[index].element;

    if (entering) {
      slides.forEach((s, k) => { s.element.dataset.state = k < index ? 'past' : k === index ? 'current' : 'future'; });
      root.dataset.currentSlide = slides[index].number;
    }
    // Miniaturen zeigen die Folie vollständig, mit allen Schritten.
    const visible = mode === 'snapshot' ? Infinity : step;
    element.querySelectorAll('[data-step]').forEach(el => {
      el.toggleAttribute('data-step-shown', (parseInt(el.dataset.step, 10) || 0) <= visible);
    });
    root.dataset.currentStep = step;

    if (entering) {
      if (previous >= 0) emit(slides[previous].element, 'presentation:leave', { index: previous, slide: outline[previous] });
      emit(element, 'presentation:enter', { index, slide });
      emit(document, 'presentation:change', { index, previous, slide });
    }
    emit(element, 'presentation:step', { index, step, steps: slide.steps, previous: previousStep });
    if (mode === 'browser') history.replaceState(null, '', '#' + encodeURIComponent(slides[index].id));
    notify({ type: 'change', index, step });
    return true;
  }

  function isTyping(target) {
    return target instanceof Element && target.closest('input, textarea, select, [contenteditable=""], [contenteditable="true"]');
  }

  function onKey(e) {
    if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey || isTyping(e.target)) return;
    const actions = {
      ArrowRight: e.shiftKey ? api.nextSection : api.next,
      ArrowLeft: e.shiftKey ? api.prevSection : api.prev,
      ' ': api.next, PageDown: api.next, PageUp: api.prev,
      Home: () => show(0), End: () => show(slides.length - 1),
      f: toggleFullscreen, F: toggleFullscreen
    };
    const action = actions[e.key];
    if (!action) return;
    e.preventDefault();
    action();
  }

  function toggleFullscreen() {
    document.fullscreenElement ? document.exitFullscreen() : root.requestFullscreen?.();
  }

  function init() {
    const style = document.createElement('style');
    style.dataset.presentationRuntime = '';
    style.textContent = BASE_CSS;
    document.head.prepend(style);

    size = readSize();
    if (size) {
      root.dataset.presentationSize = `${size.width}x${size.height}`;
      root.style.setProperty('--presentation-width', size.width + 'px');
      root.style.setProperty('--presentation-height', size.height + 'px');
      addEventListener('resize', fit);
      fit();
    }

    slides = readSlides();
    slides.forEach(s => { if (s.parent !== null) slides[s.parent].children.push(s.index); });
    slides.forEach(s => { s.element.dataset.state = 'future'; });

    document.addEventListener('click', e => {
      const target = e.target.closest?.('[data-goto], a[href^="#"]');
      if (!target) return;
      const ref = target.dataset.goto ?? target.getAttribute('href');
      if (resolve(ref) < 0) return;
      e.preventDefault();
      api.goto(ref);
    });

    // Tippt jemand in ein Eingabefeld, darf die App die Tasten nicht zum Blättern abfangen.
    document.addEventListener('focusin', e => { if (isTyping(e.target)) notify({ type: 'typing', active: true }); });
    document.addEventListener('focusout', e => { if (isTyping(e.target)) notify({ type: 'typing', active: false }); });

    if (mode === 'browser') {
      addEventListener('keydown', onKey);
      addEventListener('hashchange', () => api.goto(decodeURIComponent(location.hash.slice(1))));
    }

    const start = mode === 'browser' ? resolve(decodeURIComponent(location.hash.slice(1))) : -1;
    show(Math.max(0, start));

    const outline = api.slides;
    emit(document, 'presentation:ready', { slides: outline });
    notify({ type: 'ready', version: api.version, title: document.title, size, slides: outline, current, step });
    resolveReady(api);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
