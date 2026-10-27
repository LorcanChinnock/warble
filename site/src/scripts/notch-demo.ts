// The landing page's notch demo (NotchDemo.astro). It tours the three states by itself until the visitor touches it, and
// only ticks while it's on screen, so a page left open in another tab costs nothing.
type Scene = 'rest' | 'open' | 'idle';

const tracks = [
  { title: 'Static Bloom', artist: 'Halden Rowe', art: 'radial-gradient(circle at 68% 34%, #2b2118 0 24%, transparent 25%), #ff7db4' },
  { title: 'Low Tide Radio', artist: 'Mira Okafor', art: 'linear-gradient(160deg, transparent 0 50%, #ff7db4 50%), #fff4d0' },
  { title: 'Paper Lanterns', artist: 'The Sundays Out', art: 'repeating-linear-gradient(90deg, #ffd34e 0 6px, transparent 6px 12px), #ff7db4' },
];
const captions: Record<Scene, string> = {
  rest: "The album art on one side, a few moving bars on the other. That's all you see while you work.",
  open: 'Hover to open it in a split second: the song, progress and controls. Click and it opens at once.',
  idle: 'Nothing playing: no timers, no polling, no CPU. Point at it and it tells you so.',
};
const trackLength = 222;
const tourLength = 18;
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

// The tour: at rest, open (skipping once), at rest again, then empty.
const tourScene = (t: number): Scene => {
  const c = t % tourLength;
  return c < 3 ? 'rest' : c < 10 ? 'open' : c < 13 ? 'rest' : 'idle';
};

for (const demo of document.querySelectorAll<HTMLElement>('[data-notch-demo]')) {
  const notch = demo.querySelector<HTMLElement>('.notch')!;
  const open = demo.querySelector<HTMLElement>('.layer.open')!;
  const caption = demo.querySelector<HTMLElement>('[data-caption]')!;
  const title = demo.querySelector<HTMLElement>('[data-title]')!;
  const artist = demo.querySelector<HTMLElement>('[data-artist]')!;
  const elapsed = demo.querySelector<HTMLElement>('[data-elapsed]')!;
  const progress = demo.querySelector<HTMLElement>('[data-progress]')!;
  const toggle = demo.querySelector<HTMLButtonElement>('[data-toggle]')!;
  const dock = [...demo.querySelectorAll<HTMLButtonElement>('.dock [data-scene]')];

  let manual = reduceMotion;
  let scene: Scene = reduceMotion ? 'open' : 'rest';
  let hover = false;
  let index = 0;
  let position = 0;
  let playing = true;
  let t = 0;
  let timer: ReturnType<typeof setInterval> | undefined;

  const render = () => {
    const idle = scene === 'idle';
    const isOpen = !idle && (scene === 'open' || (manual && hover));
    const state = isOpen ? 'open' : idle && manual && hover ? 'note' : idle ? 'idle' : 'rest';
    notch.dataset.state = state;
    notch.dataset.playing = String(playing);
    open.toggleAttribute('inert', !isOpen);
    const track = tracks[index % tracks.length];
    notch.style.setProperty('--art', track.art);
    title.textContent = track.title;
    artist.textContent = track.artist;
    const seconds = Math.floor((position / 100) * trackLength);
    elapsed.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
    progress.style.width = `${position}%`;
    toggle.setAttribute('aria-label', playing ? 'Pause' : 'Play');
    caption.textContent = captions[scene];
    for (const button of dock) button.setAttribute('aria-pressed', String(button.dataset.scene === scene));
  };

  const touch = () => {
    manual = true;
    demo.dataset.touched = '';
  };

  const tick = () => {
    if (!manual) {
      t += 0.2;
      const c = t % tourLength;
      // One skip in the middle of each open stretch.
      index = (Math.floor(t / tourLength) * 2 + (c >= 7 ? 1 : 0)) % tracks.length;
      position = ((c % 14) / 14) * 100;
      scene = tourScene(t);
    } else if (playing && scene !== 'idle') {
      position = (position + 0.5) % 100;
    }
    render();
  };

  let onScreen = false;
  const start = () => {
    if (timer || document.hidden || !onScreen) return;
    // With Reduce Motion the tour doesn't run, and the bar only moves while a song plays in the open card.
    timer = setInterval(tick, 200);
  };
  const stop = () => {
    clearInterval(timer);
    timer = undefined;
  };

  notch.addEventListener('pointerenter', () => { touch(); hover = true; render(); });
  notch.addEventListener('pointerleave', () => { hover = false; render(); });
  notch.addEventListener('focusin', () => { touch(); hover = true; render(); });
  notch.addEventListener('focusout', (event) => {
    if (!notch.contains(event.relatedTarget as Node | null)) { hover = false; render(); }
  });
  notch.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') { hover = false; notch.blur(); render(); }
  });

  toggle.addEventListener('click', () => { touch(); playing = !playing; render(); });
  demo.querySelector('[data-next]')!.addEventListener('click', () => { touch(); index = (index + 1) % tracks.length; position = 0; render(); });
  demo.querySelector('[data-prev]')!.addEventListener('click', () => { touch(); index = (index + tracks.length - 1) % tracks.length; position = 0; render(); });

  for (const button of dock) {
    button.addEventListener('click', () => {
      touch();
      scene = button.dataset.scene as Scene;
      hover = false;
      playing = true;
      render();
    });
  }

  render();
  new IntersectionObserver(([entry]) => {
    onScreen = entry.isIntersecting;
    if (onScreen) start();
    else stop();
  }).observe(demo);
  document.addEventListener('visibilitychange', () => (document.hidden ? stop() : start()));
}
