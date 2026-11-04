// Chargé dans <head> sans defer : la classe est posée avant le premier rendu.
// Sans JavaScript, toutes les rubriques restent lisibles les unes sous les autres.
document.documentElement.classList.add("js");

document.addEventListener("DOMContentLoaded", () => {
  setUpTour();
  setUpCopy();
  setUpReveal();
});

function setUpTour() {
  const tour = document.querySelector("[data-tour]");
  if (!tour) return;

  const list = tour.querySelector('[role="tablist"]');
  const tabs = [...tour.querySelectorAll('[role="tab"]')];
  const overlay = tour.querySelector(".tabs-overlay");
  const stage = tour.querySelector(".stage");
  const scroller = tour.querySelector(".tabs-scroll");

  // Découpe la copie claire de la liste sur l'onglet actif.
  // Le style est posé sur l'élément lui-même pour ne pas recalculer ses enfants.
  const placeOverlay = (tab) => {
    const right = list.offsetWidth - tab.offsetLeft - tab.offsetWidth;
    overlay.style.clipPath = `inset(4px ${right}px 4px ${tab.offsetLeft}px round 999px)`;
  };

  const select = (tab, { instant = false, focus = false } = {}) => {
    // Une action au clavier se répète : elle s'applique sans animation.
    for (const element of [list, stage, tour]) element.classList.toggle("is-instant", instant);

    for (const other of tabs) {
      const selected = other === tab;
      other.setAttribute("aria-selected", String(selected));
      other.tabIndex = selected ? 0 : -1;
      const name = other.dataset.tab;
      tour.querySelector(`[data-panel="${name}"]`).classList.toggle("is-active", selected);
      tour.querySelector(`[data-glow="${name}"]`).classList.toggle("is-on", selected);
    }

    placeOverlay(tab);
    if (focus) tab.focus({ preventScroll: true });

    // Sur téléphone, garde l'onglet actif visible dans la liste défilante.
    const target = tab.offsetLeft - (scroller.clientWidth - tab.offsetWidth) / 2;
    const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
    scroller.scrollTo({ left: target, behavior: instant || reduceMotion ? "auto" : "smooth" });
  };

  tabs.forEach((tab, index) => {
    tab.tabIndex = index === 0 ? 0 : -1;
    tab.addEventListener("click", () => select(tab));
    tab.addEventListener("keydown", (event) => {
      const moves = {
        ArrowRight: (index + 1) % tabs.length,
        ArrowLeft: (index - 1 + tabs.length) % tabs.length,
        Home: 0,
        End: tabs.length - 1,
      };
      if (!(event.key in moves)) return;
      event.preventDefault();
      select(tabs[moves[event.key]], { instant: true, focus: true });
    });
  });

  // Charge toutes les rubriques à l'approche de la section : changer d'onglet ne montre jamais un cadre vide.
  const images = tour.querySelectorAll(".panel img");
  const preload = new IntersectionObserver((entries) => {
    if (!entries.some((entry) => entry.isIntersecting)) return;
    images.forEach((image) => { image.loading = "eager"; });
    preload.disconnect();
  }, { rootMargin: "800px 0px" });
  preload.observe(tour);

  const current = () => tabs.find((tab) => tab.getAttribute("aria-selected") === "true");
  const settle = () => {
    list.classList.add("is-instant");
    placeOverlay(current());
  };
  settle();
  new ResizeObserver(settle).observe(list);
  // Les polices système peuvent changer la largeur des onglets après le premier calcul.
  document.fonts?.ready.then(settle);
}

function setUpCopy() {
  for (const button of document.querySelectorAll("[data-copy]")) {
    if (!navigator.clipboard) continue;
    const source = document.getElementById(button.dataset.copy);
    const idle = button.querySelector('[data-state="idle"]');
    const done = button.querySelector('[data-state="done"]');
    let timer;

    button.hidden = false;
    button.setAttribute("aria-label", "Copier l’empreinte SHA-256");
    button.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(source.textContent.trim());
      } catch {
        return;
      }
      button.classList.add("is-done");
      button.setAttribute("aria-label", "Empreinte copiée");
      idle.setAttribute("aria-hidden", "true");
      done.removeAttribute("aria-hidden");
      clearTimeout(timer);
      timer = setTimeout(() => {
        button.classList.remove("is-done");
        button.setAttribute("aria-label", "Copier l’empreinte SHA-256");
        idle.removeAttribute("aria-hidden");
        done.setAttribute("aria-hidden", "true");
      }, 1800);
    });
  }
}

function setUpReveal() {
  const items = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window)) {
    items.forEach((item) => item.classList.add("is-visible"));
    return;
  }
  // Une seule fois : rejouer l'effet à chaque passage gênerait la lecture.
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    }
  }, { rootMargin: "0px 0px -8% 0px" });
  items.forEach((item) => observer.observe(item));
}
