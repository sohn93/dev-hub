(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.DevHub = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const normalize = (value) =>
    String(value ?? "")
      .normalize("NFKC")
      .toLocaleLowerCase("ko-KR")
      .trim();

  function cardSearchText(card, sectionLabel = "") {
    return normalize(
      [
        card.title,
        card.description,
        card.desc,
        card.project,
        card.projectLabel,
        sectionLabel,
        ...(card.tags || []),
      ].join(" ")
    );
  }

  function matchesCard(card, query = "", project = "all", sectionLabel = "") {
    const projectMatches = project === "all" || card.project === project;
    const queryMatches =
      !normalize(query) || cardSearchText(card, sectionLabel).includes(normalize(query));
    return projectMatches && queryMatches;
  }

  function sortCards(cards) {
    return [...cards].sort((a, b) => {
      if (Boolean(a.pinned) !== Boolean(b.pinned)) return a.pinned ? -1 : 1;
      return String(b.updated || "").localeCompare(String(a.updated || ""));
    });
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function allCards(data) {
    return data.sections.flatMap((section) =>
      section.cards.map((card) => ({ ...card, sectionId: section.id }))
    );
  }

  function visibleSections(data, query = "", project = "all") {
    const projectMap = new Map(data.projects.map((item) => [item.id, item]));
    return data.sections
      .map((section, sectionIndex) => ({
        ...section,
        sectionIndex,
        cards: sortCards(section.cards).filter((card) =>
          matchesCard(
            { ...card, projectLabel: projectMap.get(card.project)?.label || "" },
            query,
            project,
            section.label
          )
        ),
      }))
      .filter((section) => section.cards.length > 0);
  }

  function renderHub(data) {
    const projectBar = document.querySelector("#project-filters");
    const sectionNav = document.querySelector("#section-nav");
    const sectionRoot = document.querySelector("#document-sections");
    const search = document.querySelector("#document-search");
    const empty = document.querySelector("#empty-state");
    const countLabel = document.querySelector("#result-count");
    if (!projectBar || !sectionNav || !sectionRoot || !search || !empty) return;

    const projectMap = new Map(data.projects.map((project) => [project.id, project]));
    const flattened = allCards(data);
    let activeProject = "all";
    let disposeScrollSpy = () => {};
    let pendingRenderFrame = 0;

    const projectCount = (projectId) =>
      flattened.filter((card) => projectId === "all" || card.project === projectId).length;

    const renderFilters = () => {
      const filters = [
        { id: "all", label: "전체" },
        ...data.projects.map((project) => ({ id: project.id, label: project.label })),
      ];
      projectBar.innerHTML = filters
        .map(
          (filter) => `
            <button class="project-filter${filter.id === activeProject ? " is-active" : ""}"
              type="button" data-project="${escapeHtml(filter.id)}"
              aria-pressed="${filter.id === activeProject}">
              <span>${escapeHtml(filter.label)}</span>
              <strong>${projectCount(filter.id)}</strong>
            </button>`
        )
        .join("");
    };

    const syncFilterState = () => {
      projectBar.querySelectorAll("[data-project]").forEach((button) => {
        const selected = button.dataset.project === activeProject;
        button.classList.toggle("is-active", selected);
        button.setAttribute("aria-pressed", String(selected));
      });
    };

    const renderSections = () => {
      const query = search.value;
      const sections = visibleSections(data, query, activeProject);
      const visibleCount = sections.reduce((total, section) => total + section.cards.length, 0);

      disposeScrollSpy();
      disposeScrollSpy = () => {};
      if (pendingRenderFrame) cancelAnimationFrame(pendingRenderFrame);

      sectionNav.innerHTML = sections
        .map(
          (section, index) =>
            `<a class="section-link${index === 0 ? " is-active" : ""}" href="#${escapeHtml(
              section.id
            )}">${escapeHtml(section.label)}</a>`
        )
        .join("");

      sectionRoot.innerHTML = sections
        .map((section) => {
          const cardHtml = section.cards
            .map((card) => {
              const project = projectMap.get(card.project);
              const external = /^https?:\/\//.test(card.url);
              const tags = (card.tags || [])
                .map((tag) => `<span class="tag">${escapeHtml(tag)}</span>`)
                .join("");
              return `
                <a class="doc-card${card.pinned ? " is-pinned" : ""}"
                  href="${escapeHtml(card.url)}" ${external ? 'target="_blank" rel="noreferrer"' : ""}
                  style="--project-color: ${project?.color || "#6d5dfc"}">
                  <span class="card-main">
                    <span class="card-top">
                      <span class="project-badge">${escapeHtml(project?.label || card.project)}</span>
                      <strong class="card-title">${escapeHtml(card.title)}</strong>
                      <span class="status" data-status="${escapeHtml(card.status)}">${escapeHtml(
                        card.status
                      )}</span>
                      ${external ? '<span class="external-mark" aria-label="새 창">↗</span>' : ""}
                    </span>
                    <span class="card-description">${escapeHtml(card.description)}</span>
                    <span class="card-foot">
                      <span>${escapeHtml(card.version)}</span>
                      <time datetime="${escapeHtml(card.updated)}">${escapeHtml(card.updated)}</time>
                      ${tags}
                    </span>
                  </span>
                </a>`;
            })
            .join("");

          return `
            <section class="hub-section" id="${escapeHtml(section.id)}">
              <div class="section-head">
                <h2 class="section-title">${escapeHtml(section.label)}</h2>
                <p class="section-desc">${escapeHtml(section.description)}</p>
              </div>
              <div class="document-list">${cardHtml}</div>
            </section>`;
        })
        .join("");

      empty.hidden = visibleCount !== 0;
      if (countLabel) countLabel.textContent = `${visibleCount}개 문서`;
      pendingRenderFrame = requestAnimationFrame(() => {
        disposeScrollSpy = setupScrollSpy();
        pendingRenderFrame = 0;
      });
    };

    projectBar.addEventListener("click", (event) => {
      const button = event.target.closest("[data-project]");
      if (!button) return;
      activeProject = button.dataset.project;
      syncFilterState();
      renderSections();
    });
    sectionNav.addEventListener("click", (event) => {
      const link = event.target.closest(".section-link");
      if (!link) return;
      sectionNav.querySelectorAll(".section-link").forEach((item) => {
        item.classList.toggle("is-active", item === link);
      });
    });
    search.addEventListener("input", renderSections);

    renderFilters();
    renderSections();
  }

  function observeReveals() {
    const items = document.querySelectorAll(".reveal:not(.is-visible)");
    if (!("IntersectionObserver" in window) || matchMedia("(prefers-reduced-motion: reduce)").matches) {
      items.forEach((item) => item.classList.add("is-visible"));
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );
    items.forEach((item) => observer.observe(item));
  }

  function setupScrollSpy() {
    const links = [...document.querySelectorAll(".section-link")];
    const sections = links
      .map((link) => document.querySelector(link.getAttribute("href")))
      .filter(Boolean);
    if (!links.length || !sections.length || !("IntersectionObserver" in window)) return () => {};

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (!visible) return;
        links.forEach((link) =>
          link.classList.toggle("is-active", link.getAttribute("href") === `#${visible.target.id}`)
        );
      },
      { rootMargin: "-20% 0px -65% 0px", threshold: [0.01, 0.25, 0.6] }
    );
    sections.forEach((section) => observer.observe(section));
    return () => observer.disconnect();
  }

  function initialize() {
    observeReveals();
    const data = window.DEV_HUB_DATA;
    if (data && document.querySelector("#document-sections")) {
      const title = document.querySelector("#site-title");
      const subtitle = document.querySelector("#site-sub");
      if (title) title.textContent = data.site.title;
      if (subtitle) subtitle.textContent = data.site.description;
      renderHub(data);
      const updated = document.querySelector("#site-updated");
      if (updated) {
        updated.dateTime = data.site.updated;
        updated.textContent = `최종 업데이트 ${data.site.updated}`;
      }
    }
  }

  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", initialize, { once: true });
    } else {
      initialize();
    }
  }

  return { normalize, cardSearchText, matchesCard, sortCards, escapeHtml, visibleSections };
});

