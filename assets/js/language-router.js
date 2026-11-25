(function () {
  'use strict';

  var STORAGE_KEY = 'playnest-language';
  var isEnglishPage = /^\/en(?:\/|$)/.test(window.location.pathname);
  var query = new URLSearchParams(window.location.search);
  var requested = query.get('lang');

  function preferredLanguage() {
    if (requested === 'vi' || requested === 'en') {
      try { localStorage.setItem(STORAGE_KEY, requested); } catch (error) {}
      return requested;
    }

    try {
      var saved = localStorage.getItem(STORAGE_KEY);
      if (saved === 'vi' || saved === 'en') return saved;
    } catch (error) {}

    var languages = navigator.languages && navigator.languages.length
      ? navigator.languages
      : [navigator.language || 'vi'];
    return languages.some(function (language) {
      return String(language).toLowerCase().indexOf('vi') === 0;
    }) ? 'vi' : 'en';
  }

  var language = preferredLanguage();
  if (!isEnglishPage && language === 'en') {
    window.location.replace('/en/');
    return;
  }
  if (isEnglishPage && language === 'vi') {
    window.location.replace('/');
    return;
  }

  window.PlayNestLanguage = {
    set: function (nextLanguage) {
      try { localStorage.setItem(STORAGE_KEY, nextLanguage); } catch (error) {}
      window.location.href = nextLanguage === 'en' ? '/en/' : '/';
    }
  };

  document.addEventListener('DOMContentLoaded', function () {
    var switcher = document.createElement('button');
    switcher.type = 'button';
    switcher.className = 'playnest-language-switcher';
    switcher.textContent = isEnglishPage ? 'VI' : 'EN';
    switcher.setAttribute('aria-label', isEnglishPage ? 'Chuyển sang tiếng Việt' : 'Switch to English');
    switcher.addEventListener('click', function () {
      window.PlayNestLanguage.set(isEnglishPage ? 'vi' : 'en');
    });
    document.body.appendChild(switcher);
  });
})();
