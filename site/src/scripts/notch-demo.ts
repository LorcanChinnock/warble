// The landing page's notch demo (NotchDemo.astro). It opens once by itself a moment after it scrolls into view, closes again, and
// from then on belongs to the visitor. Nothing ticks while it is closed or off screen, so a page left open in another tab costs nothing.
type Track = { title: string; artist: string; album: string; art: string; duration: number; glow: [string, string] };

// Real songs, as the app would show them. The glow is the cover's two main colours, as the app's own would be.
const tracks: Track[] = [
  { title: 'A Moment Apart', artist: 'ODESZA', album: 'A Moment Apart', art: 'moment-apart', duration: 234.244, glow: ['31 111 139', '20 64 90'] },
  { title: 'Take On Me', artist: 'a-ha', album: 'Hunting High and Low', art: 'take-on-me', duration: 228.48, glow: ['120 120 122', '100 100 100'] },
  { title: 'Nightcall', artist: 'Kavinsky', album: 'Nightcall', art: 'nightcall', duration: 258.413, glow: ['20 90 160', '30 80 150'] },
  { title: 'Blinding Lights', artist: 'The Weeknd', album: 'After Hours', art: 'blinding-lights', duration: 200.046, glow: ['130 105 60', '150 120 70'] },
  { title: 'WannaCry', artist: 'Ninajirachi & Porter Robinson', album: 'WannaCry', art: 'wannacry', duration: 219.367, glow: ['118 129 90', '110 126 114'] },
  { title: 'Lights Burn Dimmer', artist: 'Fred again.. & Jamie T', album: 'Lights Burn Dimmer', art: 'lights-burn-dimmer', duration: 260.879, glow: ['50 50 56', '40 40 46'] },
  { title: '777', artist: 'Joji', album: 'Nectar', art: '777', duration: 181.772, glow: ['150 48 52', '90 30 34'] },
  { title: 'Cracker Island (feat. Thundercat)', artist: 'Gorillaz', album: 'Cracker Island', art: 'cracker-island', duration: 213.75, glow: ['160 72 102', '150 102 111'] },
  { title: 'The Distance', artist: 'CAKE', album: 'Fashion Nugget', art: 'the-distance', duration: 180.628, glow: ['190 170 120', '200 180 125'] },
];
const startPosition = 18.4;
const openDelay = 1800;
const openFor = 5500;
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

const label = (seconds: number) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;

/** A slider that follows a drag along its rail, and the arrow keys. `set` takes a fraction from 0 to 1. */
const slider = (rail: HTMLElement, get: () => number, set: (fraction: number) => void) => {
  const at = (event: PointerEvent) => {
    const box = rail.getBoundingClientRect();
    set(Math.min(Math.max((event.clientX - box.left) / box.width, 0), 1));
  };
  rail.addEventListener('pointerdown', (event) => {
    rail.setPointerCapture(event.pointerId);
    at(event);
  });
  rail.addEventListener('pointermove', (event) => {
    if (rail.hasPointerCapture(event.pointerId)) at(event);
  });
  rail.addEventListener('keydown', (event) => {
    const step = event.key === 'ArrowRight' || event.key === 'ArrowUp' ? 0.05 : event.key === 'ArrowLeft' || event.key === 'ArrowDown' ? -0.05 : 0;
    if (!step) return;
    event.preventDefault();
    set(Math.min(Math.max(get() + step, 0), 1));
  });
};

for (const demo of document.querySelectorAll<HTMLElement>('[data-notch-demo]')) {
  const notch = demo.querySelector<HTMLElement>('.notch')!;
  const open = demo.querySelector<HTMLElement>('.layer.open')!;
  const volume = demo.querySelector<HTMLElement>('.volume')!;
  const volumeRail = volume.querySelector<HTMLElement>('.rail')!;
  const positionRail = demo.querySelector<HTMLElement>('.scrub .rail')!;
  const elapsed = demo.querySelector<HTMLElement>('[data-elapsed]')!;
  const remaining = demo.querySelector<HTMLElement>('[data-remaining]')!;
  const toggle = demo.querySelector<HTMLButtonElement>('[data-toggle]')!;
  const shuffleButton = demo.querySelector<HTMLButtonElement>('[data-shuffle]')!;
  const repeatButton = demo.querySelector<HTMLButtonElement>('[data-repeat]')!;

  let tourOpen = false;
  let hover = false;
  let playing = true;
  let index = 0;
  let shown = -1;
  let position = startPosition;
  let level = 0.25;
  let shuffle = false;
  let repeat: 'off' | 'all' | 'one' = 'off';
  const history: number[] = [];
  let tour: ReturnType<typeof setTimeout>[] = [];
  let timer: ReturnType<typeof setInterval> | undefined;
  let onScreen = false;

  const text = (name: string, value: string) => {
    for (const element of demo.querySelectorAll(`[data-${name}]`)) element.textContent = value;
  };

  const render = () => {
    const track = tracks[index];
    if (shown !== index) {
      shown = index;
      text('title', track.title);
      text('artist', track.artist);
      text('album', track.album);
      for (const image of demo.querySelectorAll('img')) image.src = `/media/art-${track.art}.webp`;
      notch.style.setProperty('--glow-a', track.glow[0]);
      notch.style.setProperty('--glow-b', track.glow[1]);
    }
    const isOpen = tourOpen || hover;
    notch.dataset.state = isOpen ? 'open' : 'rest';
    notch.dataset.playing = String(playing);
    open.toggleAttribute('inert', !isOpen);
    elapsed.textContent = label(position);
    remaining.textContent = `-${label(track.duration - position)}`;
    positionRail.style.setProperty('--played', String(position / track.duration));
    positionRail.setAttribute('aria-valuenow', String(Math.floor(position)));
    positionRail.setAttribute('aria-valuemax', String(Math.floor(track.duration)));
    positionRail.setAttribute('aria-valuetext', `${label(position)} of ${label(track.duration)}`);
    volumeRail.style.setProperty('--played', String(level));
    volumeRail.setAttribute('aria-valuenow', String(Math.round(level * 100)));
    volume.dataset.muted = String(level === 0);
    toggle.setAttribute('aria-label', playing ? 'Pause' : 'Play');
    shuffleButton.setAttribute('aria-pressed', String(shuffle));
    repeatButton.dataset.mode = repeat;
    repeatButton.setAttribute('aria-label', `Repeat: ${repeat}`);
    // The clock runs only while the card is open and the song plays.
    if (isOpen && playing && onScreen && !document.hidden) {
      timer ??= setInterval(() => {
        position += 0.5;
        if (position >= tracks[index].duration) finish();
        render();
      }, 500);
    } else {
      clearInterval(timer);
      timer = undefined;
    }
  };

  const go = (to: number, remember = true) => {
    if (remember) history.push(index);
    index = (to + tracks.length) % tracks.length;
    position = 0;
  };

  // Shuffle picks any other song, otherwise the next one along.
  const upNext = () => {
    if (!shuffle) return index + 1;
    const other = Math.floor(Math.random() * (tracks.length - 1));
    return other >= index ? other + 1 : other;
  };

  // What happens when a song ends: repeat one plays it again, and with nothing repeating the last song is the end.
  const finish = () => {
    if (repeat === 'one') position = 0;
    else if (repeat === 'off' && !shuffle && index === tracks.length - 1) {
      position = tracks[index].duration;
      playing = false;
    } else go(upNext());
  };

  const endTour = () => {
    for (const id of tour) clearTimeout(id);
    tour = [];
    tourOpen = false;
  };

  const beginTour = () => {
    tour = [
      setTimeout(() => { tourOpen = true; render(); }, openDelay),
      setTimeout(() => { tourOpen = false; render(); }, openDelay + openFor),
    ];
  };

  const enter = () => { endTour(); hover = true; render(); };
  const leave = () => { hover = false; render(); };
  notch.addEventListener('pointerenter', enter);
  notch.addEventListener('pointerleave', leave);
  notch.addEventListener('focusin', enter);
  notch.addEventListener('focusout', (event) => {
    if (!notch.contains(event.relatedTarget as Node | null)) leave();
  });
  notch.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') { hover = false; notch.blur(); render(); }
  });

  toggle.addEventListener('click', () => { playing = !playing; render(); });
  // Previous restarts a song that has been going a few seconds, and otherwise goes back one, as the app does.
  demo.querySelector('[data-prev]')!.addEventListener('click', () => {
    if (position > 3) position = 0;
    else go(history.pop() ?? index - 1, false);
    render();
  });
  demo.querySelector('[data-next]')!.addEventListener('click', () => { go(upNext()); render(); });
  shuffleButton.addEventListener('click', () => { shuffle = !shuffle; render(); });
  repeatButton.addEventListener('click', () => { repeat = repeat === 'off' ? 'all' : repeat === 'all' ? 'one' : 'off'; render(); });
  slider(volumeRail, () => level, (fraction) => { level = fraction; render(); });
  slider(positionRail, () => position / tracks[index].duration, (fraction) => { position = fraction * tracks[index].duration; render(); });

  render();
  let toured = reduceMotion;
  new IntersectionObserver(([entry]) => {
    onScreen = entry.isIntersecting;
    if (onScreen && !toured) {
      toured = true;
      beginTour();
    }
    render();
  }, { threshold: 0.5 }).observe(demo);
  document.addEventListener('visibilitychange', render);
}
