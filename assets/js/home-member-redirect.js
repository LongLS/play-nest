(function () {
  "use strict";
  const config = window.playnestSupabaseConfig;
  const library = window.supabase;
  if (!config || !library || typeof library.createClient !== "function") return;

  const client = library.createClient(config.url, config.publishableKey);
  client.auth.getSession().then(async function (result) {
    if (!result.data.session) return;
    const profile = await client.rpc("customer_club_profile");
    if (!profile.error && profile.data) window.location.replace("club/");
  }).catch(function () {
    // Trang chủ vẫn hoạt động bình thường nếu kiểm tra phiên đăng nhập thất bại.
  });
})();
