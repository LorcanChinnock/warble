// The copy button on each install command, from Copy.astro and the guide's sh code blocks.
for (const button of document.querySelectorAll<HTMLButtonElement>('[data-copy]')) {
  // Screen readers don't reliably read a button's new label, so the live region says it too.
  const status = button.nextElementSibling!;
  let reset: ReturnType<typeof setTimeout> | undefined;
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy!);
      button.textContent = 'Copied';
      status.textContent = 'Copied to the clipboard';
    } catch {
      button.textContent = 'Press ⌘C';
      status.textContent = 'Selected. Press Command-C to copy.';
      const range = document.createRange();
      range.selectNodeContents(button.previousElementSibling!);
      getSelection()?.removeAllRanges();
      getSelection()?.addRange(range);
    }
    clearTimeout(reset);
    reset = setTimeout(() => {
      button.textContent = 'Copy';
      status.textContent = '';
    }, 1600);
  });
}
