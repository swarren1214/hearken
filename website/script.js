const menuToggle = document.querySelector(".menu-toggle");
const navLinks = document.querySelector(".nav-links");

menuToggle.addEventListener("click", () => {
  const isOpen = menuToggle.getAttribute("aria-expanded") === "true";
  menuToggle.setAttribute("aria-expanded", String(!isOpen));
  navLinks.classList.toggle("is-open", !isOpen);
});

navLinks.addEventListener("click", (event) => {
  if (event.target.closest("a")) {
    menuToggle.setAttribute("aria-expanded", "false");
    navLinks.classList.remove("is-open");
  }
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && menuToggle.getAttribute("aria-expanded") === "true") {
    menuToggle.setAttribute("aria-expanded", "false");
    navLinks.classList.remove("is-open");
    menuToggle.focus();
  }
});

document.querySelector("#year").textContent = String(new Date().getFullYear());

// The screenshot gallery (images from scripts/screenshots.sh): drop any screenshot that
// isn't there, and the whole section, with its menu link, if none are.
const screens = document.querySelector(".screens");
if (screens) {
  const shots = [...screens.querySelectorAll(".screen-shot")];
  const screensLink = document.querySelector('a[href="#screens"]');
  const hideMissing = (shot) => {
    shot.hidden = true;
    screens.hidden = shots.every((each) => each.hidden);
    if (screensLink) screensLink.hidden = screens.hidden;
  };
  for (const shot of shots) {
    const image = shot.querySelector("img");
    if (image.complete && image.naturalWidth === 0) hideMissing(shot);
    else image.addEventListener("error", () => hideMissing(shot));
  }
}
