(function () {
  "use strict";
  let client;
  let profile;
  let currentMember;
  let currentSettings;

  const byId = function (id) { return document.getElementById(id); };
  const money = function (value) { return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 0 }).format(Number(value) || 0); };
  const escapeText = function (value) { return String(value == null ? "" : value); };

  function notice(message, state) {
    const box = byId("admin-notice");
    box.textContent = message || "";
    box.dataset.state = state || "";
    box.hidden = !message;
    if (message) window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function rpc(name, args) {
    const result = await client.rpc(name, args || {});
    if (result.error) throw result.error;
    return result.data;
  }

  function showPanel(id) {
    document.querySelectorAll(".ops-panel").forEach(function (panel) { panel.classList.toggle("is-active", panel.id === id); });
    document.querySelectorAll(".ops-nav button").forEach(function (button) { button.classList.toggle("is-active", button.dataset.panel === id); });
  }

  function renderMember(member) {
    currentMember = member || null;
    const box = byId("member-result");
    if (!member) { box.hidden = true; return; }
    box.replaceChildren();
    [["Mã thành viên", member.member_code], ["Số điện thoại", member.masked_phone], ["Tên", member.display_name || "Chưa cập nhật"], ["Điểm khả dụng", member.available_points], ["Điểm chờ", member.pending_points], ["Lượt ghé", member.visit_count]].forEach(function (item) {
      const div = document.createElement("div"); const span = document.createElement("span"); const strong = document.createElement("strong");
      span.textContent = item[0]; strong.textContent = escapeText(item[1]); div.append(span, strong); box.appendChild(div);
    });
    box.hidden = false;
    byId("earn-member-code").value = member.member_code;
    byId("redeem-member-code").value = member.member_code;
  }

  async function lookup(phone) {
    const rows = await rpc("lookup_member", { p_phone: phone });
    const member = rows && rows[0];
    renderMember(member);
    byId("member-create-box").hidden = Boolean(member);
    if (!member) notice("Chưa tìm thấy thành viên. Có thể tạo mới sau khi khách đồng ý.", "success");
    return member;
  }

  async function loadDashboard() {
    if (profile.role !== "manager") return;
    const data = await rpc("membership_dashboard", {});
    const map = { "m-total": data.total_members, "m-new": data.new_members, "m-visits": data.visits, "m-returning": data.returning_members, "m-pending": data.pending, "m-earned": data.points_earned, "m-redeemed": data.points_redeemed, "m-rewards": data.rewards_redeemed, "m-spend": money(data.spend), "m-abnormal": data.abnormal };
    Object.keys(map).forEach(function (id) { byId(id).textContent = escapeText(map[id]); });
  }

  async function loadRewards() {
    const result = await client.from("rewards").select("id,name,points_cost,voucher_value,conditions,valid_days").eq("active", true).order("points_cost");
    if (result.error) throw result.error;
    const select = byId("redeem-reward"); select.replaceChildren(new Option("Chọn phần thưởng", ""));
    const grid = byId("reward-list"); grid.replaceChildren();
    result.data.forEach(function (reward) {
      select.add(new Option(reward.name + " — " + reward.points_cost + " điểm", reward.id));
      const card = document.createElement("article"); const title = document.createElement("strong"); const text = document.createElement("p");
      title.textContent = reward.name + " · " + reward.points_cost + " điểm"; text.textContent = reward.conditions || "Không có điều kiện bổ sung"; card.append(title, text); grid.appendChild(card);
    });
  }

  async function loadSettings() {
    const result = await client.from("program_settings").select("*").single();
    if (result.error) throw result.error;
    currentSettings = result.data;
    byId("setting-spend").value = result.data.spend_per_point; byId("setting-expiry").value = result.data.point_expiry_months;
    byId("setting-abnormal").value = result.data.abnormal_invoice_amount; byId("setting-return-points").value = result.data.return_bonus_points;
    byId("setting-return-days").value = result.data.return_within_days; byId("setting-policy").value = result.data.policy_version;
  }

  async function loadPending() {
    if (profile.role !== "manager") return;
    const result = await client.from("pending_earn_requests").select("*").order("created_at", { ascending: false });
    if (result.error) throw result.error;
    const body = byId("pending-list"); body.replaceChildren(); byId("pending-empty").hidden = result.data.length > 0;
    result.data.forEach(function (item) {
      const row = document.createElement("tr");
      [item.invoice_code, item.member_code + "\n" + item.masked_phone, money(item.eligible_amount), item.points + (item.abnormal ? " ⚠" : ""), item.submitted_by_name].forEach(function (value) { const td = document.createElement("td"); td.textContent = value; row.appendChild(td); });
      const actions = document.createElement("td"); const approve = document.createElement("button"); const reject = document.createElement("button");
      approve.className = "table-action approve"; reject.className = "table-action"; approve.textContent = "Duyệt"; reject.textContent = "Từ chối";
      approve.addEventListener("click", function () { review(item.id, true); }); reject.addEventListener("click", function () { review(item.id, false); }); actions.append(approve, reject); row.appendChild(actions); body.appendChild(row);
    });
  }

  async function review(id, approve) {
    const reason = window.prompt(approve ? "Ghi chú đối soát (tùy chọn):" : "Lý do từ chối:");
    if (reason === null || (!approve && !reason.trim())) return;
    if (!window.confirm(approve ? "Xác nhận hóa đơn hợp lệ và cộng điểm?" : "Xác nhận từ chối yêu cầu?")) return;
    try { await rpc("review_earn_request", { p_request_id: id, p_approve: approve, p_reason: reason }); notice("Đã xử lý yêu cầu.", "success"); await Promise.all([loadPending(), loadDashboard()]); } catch (error) { notice(error.message, "error"); }
  }

  function bindForms() {
    byId("member-lookup-form").addEventListener("submit", async function (event) { event.preventDefault(); try { notice("", ""); await lookup(byId("member-phone").value); } catch (error) { notice(error.message, "error"); } });
    byId("member-create-form").addEventListener("submit", async function (event) { event.preventDefault(); try { const rows = await rpc("create_member", { p_phone: byId("member-phone").value, p_name: byId("member-name").value, p_membership_consent: byId("member-consent").checked, p_marketing_consent: byId("marketing-consent").checked, p_policy_version: "2026-11-demo" }); renderMember(rows[0]); byId("member-create-box").hidden = true; notice("Đã tạo thành viên.", "success"); } catch (error) { notice(error.message, "error"); } });
    byId("earn-form").addEventListener("submit", async function (event) { event.preventDefault(); if (!currentMember) return notice("Hãy tra cứu thành viên trước.", "error"); if (!window.confirm("Gửi yêu cầu tích điểm để quản lý đối soát?")) return; try { await rpc("submit_earn_request", { p_member_id: currentMember.id, p_invoice_code: byId("earn-invoice").value, p_paid_amount: Number(byId("earn-paid").value), p_eligible_amount: Number(byId("earn-eligible").value), p_occurred_at: new Date(byId("earn-time").value).toISOString(), p_room_type: byId("earn-room").value, p_applied_program: byId("earn-program").value || null }); notice("Đã gửi yêu cầu, điểm đang chờ quản lý duyệt.", "success"); event.target.reset(); byId("earn-member-code").value = currentMember.member_code; await lookup(byId("member-phone").value); } catch (error) { notice(error.message, "error"); } });
    byId("redeem-form").addEventListener("submit", async function (event) { event.preventDefault(); if (!currentMember) return notice("Hãy tra cứu thành viên trước.", "error"); if (!window.confirm("Đã xác minh khách và xác nhận trừ điểm đổi quà?")) return; try { await rpc("redeem_reward", { p_member_id: currentMember.id, p_reward_id: byId("redeem-reward").value, p_method: byId("redeem-method").value, p_note: byId("redeem-note").value }); notice("Đổi quà thành công.", "success"); await lookup(byId("member-phone").value); event.target.reset(); byId("redeem-member-code").value = currentMember.member_code; } catch (error) { notice(error.message, "error"); } });
    byId("settings-form").addEventListener("submit", async function (event) { event.preventDefault(); if (!window.confirm("Thay đổi này chỉ áp dụng cho giao dịch mới. Tiếp tục?")) return; try { await rpc("update_program_settings", { p_spend_per_point: Number(byId("setting-spend").value), p_point_expiry_months: Number(byId("setting-expiry").value), p_abnormal_invoice_amount: Number(byId("setting-abnormal").value), p_return_bonus_points: Number(byId("setting-return-points").value), p_return_within_days: Number(byId("setting-return-days").value), p_policy_version: byId("setting-policy").value }); notice("Đã lưu cấu hình chương trình.", "success"); await loadSettings(); } catch (error) { notice(error.message, "error"); } });
    byId("reward-form").addEventListener("submit", async function (event) { event.preventDefault(); try { await rpc("save_reward", { p_id: null, p_name: byId("reward-name").value, p_points_cost: Number(byId("reward-points").value), p_voucher_value: byId("reward-value").value ? Number(byId("reward-value").value) : null, p_conditions: byId("reward-conditions").value, p_valid_days: byId("reward-days").value ? Number(byId("reward-days").value) : null, p_active: byId("reward-active").checked }); notice("Đã thêm phần thưởng.", "success"); event.target.reset(); byId("reward-active").checked = true; await loadRewards(); } catch (error) { notice(error.message, "error"); } });
    byId("staff-form").addEventListener("submit", async function (event) { event.preventDefault(); if (!window.confirm("Xác nhận thay đổi quyền tài khoản này?")) return; try { await rpc("save_staff_access", { p_email: byId("staff-email").value, p_display_name: byId("staff-name").value, p_role: byId("staff-role").value, p_active: byId("staff-active").checked, p_can_redeem: byId("staff-redeem").checked }); notice("Đã cập nhật quyền nhân viên.", "success"); event.target.reset(); byId("staff-active").checked = true; } catch (error) { notice(error.message, "error"); } });
  }

  async function initialize(event) {
    client = event.detail.client; profile = event.detail.profile;
    byId("ops-user-name").textContent = profile.display_name || event.detail.session.user.email;
    byId("ops-user-role").textContent = profile.role === "manager" ? "Quản lý" : "Nhân viên";
    document.querySelectorAll("[data-manager-only]").forEach(function (node) { node.hidden = profile.role !== "manager"; });
    document.querySelectorAll(".ops-nav button").forEach(function (button) { button.addEventListener("click", function () { showPanel(button.dataset.panel); }); });
    byId("membership-refresh").addEventListener("click", loadDashboard); byId("pending-refresh").addEventListener("click", loadPending);
    byId("earn-time").value = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    bindForms();
    try { await Promise.all([loadDashboard(), loadRewards(), loadSettings(), loadPending()]); } catch (error) { notice("Membership chưa sẵn sàng: " + error.message + ". Hãy chạy migration Supabase mới.", "error"); }
  }

  document.addEventListener("playnest:admin-ready", initialize);
})();
