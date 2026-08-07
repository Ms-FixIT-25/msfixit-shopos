<?php
declare(strict_types=1);

function uxEscape(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function uxAllowedLocale(string $locale): string
{
    return in_array($locale, ['de-AT', 'de-DE', 'en-GB', 'en-US'], true) ? $locale : 'de-AT';
}

function uxAllowedTheme(string $theme): string
{
    return in_array($theme, ['system', 'light', 'dark'], true) ? $theme : 'system';
}

function uxWizardState(array $steps, string $current): array
{
    if ($steps === [] || count($steps) !== count(array_unique($steps, SORT_STRING))) {
        throw new InvalidArgumentException('Wizard-Schritte müssen eindeutig sein.');
    }
    foreach ($steps as $step) {
        if (!is_string($step) || !preg_match('/^[a-z][a-z0-9-]{1,48}$/', $step)) {
            throw new InvalidArgumentException('Ungültiger Wizard-Schritt.');
        }
    }
    $index = array_search($current, $steps, true);
    if ($index === false) {
        throw new InvalidArgumentException('Unbekannter Wizard-Schritt.');
    }
    return [
        'current' => $current,
        'index' => $index,
        'number' => $index + 1,
        'total' => count($steps),
        'progress' => (int)round((($index + 1) / count($steps)) * 100),
        'previous' => $index > 0 ? $steps[$index - 1] : null,
        'next' => $index < count($steps) - 1 ? $steps[$index + 1] : null,
        'complete' => $index === count($steps) - 1,
    ];
}

function uxFlash(string $type, string $title, string $message): array
{
    $allowed = ['success', 'info', 'warning', 'error'];
    if (!in_array($type, $allowed, true)) {
        $type = 'info';
    }
    return ['type' => $type, 'title' => $title, 'message' => $message];
}

function uxRenderFlash(array $flash): string
{
    $type = (string)($flash['type'] ?? 'info');
    $role = $type === 'error' ? 'alert' : 'status';
    return '<section class="so-notice so-notice--' . uxEscape($type) . '" role="' . $role . '">'
        . '<strong>' . uxEscape((string)($flash['title'] ?? 'Hinweis')) . '</strong>'
        . '<p>' . uxEscape((string)($flash['message'] ?? '')) . '</p></section>';
}
