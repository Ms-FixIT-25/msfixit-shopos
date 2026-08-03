(() => {
    'use strict';

    const settings = window.MsFixITDiscovery || {};
    const minimumCharacters = Number(settings.minimumCharacters || 2);
    let requestController = null;

    const closeSuggestions = (container) => {
        container.hidden = true;
        container.innerHTML = '';
        container.dataset.activeIndex = '-1';
    };

    const selectSuggestion = (container, index) => {
        const options = Array.from(container.querySelectorAll('[role="option"]'));
        options.forEach((option, optionIndex) => {
            const selected = optionIndex === index;
            option.setAttribute('aria-selected', selected ? 'true' : 'false');
            option.classList.toggle('is-active', selected);
            if (selected) {
                option.scrollIntoView({ block: 'nearest' });
            }
        });
        container.dataset.activeIndex = String(index);
    };

    const renderSuggestions = (container, rows) => {
        container.innerHTML = '';
        if (!Array.isArray(rows) || rows.length === 0) {
            closeSuggestions(container);
            return;
        }

        rows.forEach((row, index) => {
            const link = document.createElement('a');
            link.href = row.url;
            link.className = 'msfixit-suggestion';
            link.setAttribute('role', 'option');
            link.setAttribute('aria-selected', 'false');
            link.dataset.index = String(index);

            const image = document.createElement('img');
            image.src = row.image;
            image.alt = '';
            image.loading = 'lazy';
            image.width = 52;
            image.height = 52;

            const text = document.createElement('span');
            text.className = 'msfixit-suggestion-text';

            const title = document.createElement('strong');
            title.textContent = row.title;
            text.appendChild(title);

            if (row.summary) {
                const summary = document.createElement('small');
                summary.textContent = row.summary;
                text.appendChild(summary);
            }

            const price = document.createElement('span');
            price.className = 'msfixit-suggestion-price';
            price.textContent = row.price || '';

            link.append(image, text, price);
            container.appendChild(link);
        });

        container.hidden = false;
        container.dataset.activeIndex = '-1';
    };

    const fetchSuggestions = async (input, container) => {
        const query = input.value.trim();
        if (query.length < minimumCharacters || !settings.suggestionsUrl) {
            closeSuggestions(container);
            return;
        }

        if (requestController) {
            requestController.abort();
        }
        requestController = new AbortController();

        try {
            const url = new URL(settings.suggestionsUrl, window.location.origin);
            url.searchParams.set('q', query);
            const response = await fetch(url.toString(), {
                signal: requestController.signal,
                credentials: 'same-origin',
                headers: { Accept: 'application/json' },
            });
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            renderSuggestions(container, await response.json());
        } catch (error) {
            if (error.name !== 'AbortError') {
                closeSuggestions(container);
            }
        }
    };

    document.querySelectorAll('.msfixit-discovery-search').forEach((form) => {
        const input = form.querySelector('input[type="search"]');
        const container = form.querySelector('.msfixit-search-suggestions');
        if (!input || !container) {
            return;
        }

        let timer = null;
        input.addEventListener('input', () => {
            window.clearTimeout(timer);
            timer = window.setTimeout(() => fetchSuggestions(input, container), 180);
        });

        input.addEventListener('keydown', (event) => {
            if (container.hidden) {
                return;
            }
            const options = Array.from(container.querySelectorAll('[role="option"]'));
            if (options.length === 0) {
                return;
            }
            let active = Number(container.dataset.activeIndex || -1);
            if (event.key === 'ArrowDown') {
                event.preventDefault();
                active = (active + 1) % options.length;
                selectSuggestion(container, active);
            } else if (event.key === 'ArrowUp') {
                event.preventDefault();
                active = active <= 0 ? options.length - 1 : active - 1;
                selectSuggestion(container, active);
            } else if (event.key === 'Enter' && active >= 0) {
                event.preventDefault();
                options[active].click();
            } else if (event.key === 'Escape') {
                closeSuggestions(container);
            }
        });

        document.addEventListener('click', (event) => {
            if (!form.contains(event.target)) {
                closeSuggestions(container);
            }
        });
    });

    document.querySelectorAll('.msfixit-filter-toggle').forEach((button) => {
        const target = document.getElementById(button.getAttribute('aria-controls'));
        if (!target) {
            return;
        }
        button.addEventListener('click', () => {
            const expanded = button.getAttribute('aria-expanded') === 'true';
            button.setAttribute('aria-expanded', expanded ? 'false' : 'true');
            target.classList.toggle('is-open', !expanded);
            button.textContent = expanded ? 'Filter anzeigen' : 'Filter schließen';
        });
    });
})();
