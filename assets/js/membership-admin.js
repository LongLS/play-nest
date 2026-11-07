(function () {
  "use strict";
  let client;
  let profile;
  let currentMember;
  let currentSettings;
  const pages = { members: 1, earns: 1, redemptions: 1, activity: 1 };
  const pageSize = 15;

  const byId = function (id) { return document.getElementById(id); };
  const money = function (value) { return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 0 }).format(Number(value) || 0); };
  const escapeText = function (value) { return String(value == null ? "" : value); };
  const staffLoginEmail = function(value) { const login=String(value||"").trim().toLowerCase();if(login.includes("@"))return login;if(!/^[a-z0-9._-]{3,40}$/.test(login))throw new Error("Tên đăng nhập không hợp lệ");return login+"@staff.playnest.vn"; };
  const staffUsername = function(value) { const email=String(value||"");const suffix="@staff.playnest.vn";return email.endsWith(suffix)?email.slice(0,-suffix.length):email; };
  const formatDate = function (value) { return value ? new Intl.DateTimeFormat("vi-VN", { dateStyle: "short", timeStyle: "short" }).format(new Date(value)) : "—"; };
  const dateStart = function (id) { return byId(id).value ? new Date(byId(id).value + "T00:00:00").toISOString() : null; };
  const dateEnd = function (id) { if (!byId(id).value) return null; const date = new Date(byId(id).value + "T00:00:00"); date.setDate(date.getDate() + 1); return date.toISOString(); };

  function cell(value, className) { const td = document.createElement("td"); td.textContent = escapeText(value); if (className) td.className = className; return td; }
  function statusLabel(value) {
    const labels = { pending: "Chờ duyệt", approved: "Đã duyệt", rejected: "Từ chối/đã hủy", reversed: "Đã đảo điểm" };
    const span = document.createElement("span"); span.className = "status-pill " + (value === "approved" ? "status-pill--success" : value === "pending" ? "status-pill--warning" : "status-pill--danger"); span.textContent = labels[value] || value; return span;
  }
  function renderPagination(id, data, onPage) {
    const box = byId(id); box.replaceChildren(); const totalPages = Math.max(1, Math.ceil(Number(data.total || 0) / Number(data.page_size || pageSize)));
    const previous = document.createElement("button"); const next = document.createElement("button"); const text = document.createElement("span");
    previous.textContent = "‹"; next.textContent = "›"; text.textContent = "Trang " + data.page + "/" + totalPages + " · " + data.total + " bản ghi";
    previous.disabled = data.page <= 1; next.disabled = data.page >= totalPages;
    previous.addEventListener("click", function () { onPage(data.page - 1); }); next.addEventListener("click", function () { onPage(data.page + 1); }); box.append(previous, text, next);
  }

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

  async function issueMemberPassword(member, reset) {
    if (reset && !window.confirm("Cấp mật khẩu tạm mới sẽ vô hiệu hóa mật khẩu hiện tại. Tiếp tục?")) return;
    const sessionResult=await client.auth.getSession();const token=sessionResult.data.session&&sessionResult.data.session.access_token;if(!token)throw new Error("Phiên đăng nhập đã hết hạn");
    const response=await fetch(window.playnestSupabaseConfig.url+"/functions/v1/manage-member-auth",{method:"POST",headers:{"Content-Type":"application/json","Authorization":"Bearer "+token,"apikey":window.playnestSupabaseConfig.publishableKey},body:JSON.stringify({member_id:member.id})});
    const data=await response.json();if(!response.ok)throw new Error(data.error||"Không thể cấp mật khẩu");
    byId("member-temporary-password").textContent=data.temporary_password;byId("member-password-dialog").showModal();
  }

  function showPanel(id) {
    if (!byId(id)) id = "membership-overview";
    document.querySelectorAll(".ops-panel").forEach(function (panel) { panel.classList.toggle("is-active", panel.id === id); });
    document.querySelectorAll(".ops-nav button").forEach(function (button) { button.classList.toggle("is-active", button.dataset.panel === id); });
    if (window.location.hash !== "#" + id) window.history.replaceState(null, "", "#" + id);
  }

  function lookupStatus(message, state) {
    const box = byId("member-lookup-status");
    box.textContent = message || ""; box.dataset.state = state || ""; box.hidden = !message;
  }

  function overviewDates() {
    const now = new Date(); const range = byId("overview-range").value; const from = new Date(now);
    if (range === "today") from.setHours(0,0,0,0); else if (range === "month") { from.setDate(1); from.setHours(0,0,0,0); } else from.setDate(from.getDate() - Number(range || 30));
    return { from: from, to: now };
  }

  function renderBars(id, rows, key, secondaryKey) {
    const box=byId(id);box.replaceChildren();const max=Math.max(1,...rows.map(function(row){return Math.max(Number(row[key])||0,secondaryKey?Number(row[secondaryKey])||0:0);}));rows.forEach(function(row){const bar=document.createElement("div");bar.className="chart-bar";bar.style.height=Math.max(3,Math.round((Number(row[key])||0)/max*100))+"%";bar.title=row.day+": "+row[key];box.appendChild(bar);if(secondaryKey){const second=document.createElement("div");second.className="chart-bar chart-bar--secondary";second.style.height=Math.max(3,Math.round((Number(row[secondaryKey])||0)/max*100))+"%";second.title=row.day+": "+row[secondaryKey];box.appendChild(second);}});
  }

  async function loadOverviewSeries(dates) {
    if(profile.role!=="manager")return;const data=await rpc("admin_overview_series",{p_from:dates.from.toISOString(),p_to:dates.to.toISOString()});renderBars("chart-members",data.daily,"new_members");renderBars("chart-visits",data.daily,"visits");renderBars("chart-points",data.daily,"points_earned","points_used");const rewards=byId("chart-rewards");rewards.replaceChildren();(data.top_rewards||[]).forEach(function(item){const row=document.createElement("div"),name=document.createElement("span"),count=document.createElement("strong");name.textContent=item.name;count.textContent=item.redemptions+" lượt";row.append(name,count);rewards.appendChild(row);});if(!(data.top_rewards||[]).length)rewards.textContent="Chưa có lượt đổi quà trong kỳ.";const recent=byId("overview-recent");recent.replaceChildren();(data.recent_activity||[]).forEach(function(item){const row=document.createElement("div"),name=document.createElement("span"),time=document.createElement("strong");name.textContent=(item.actor_name||"Hệ thống")+" · "+item.action;time.textContent=formatDate(item.created_at);row.append(name,time);recent.appendChild(row);});if(!(data.recent_activity||[]).length)recent.textContent="Chưa có hoạt động.";
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
    if (byId("redeem-member-code")) byId("redeem-member-code").value = member.member_code;
    if(profile.role==="manager"){const reset=document.createElement("button");reset.type="button";reset.className="admin-button admin-button--ghost";reset.textContent="Cấp lại mật khẩu tạm";reset.addEventListener("click",async function(){try{await issueMemberPassword(member,true);}catch(error){notice(error.message,"error");}});box.appendChild(reset);}
  }

  async function lookup(phone) {
    lookupStatus("Đang tra cứu…", "loading");
    const rows = await rpc("lookup_member", { p_phone: phone });
    const member = rows && rows[0];
    renderMember(member);
    const createBox = byId("member-create-box");
    createBox.hidden = Boolean(member); createBox.open = !member;
    lookupStatus(member ? "Đã tìm thấy " + member.member_code + "." : "Chưa có thành viên. Hãy xác nhận sự đồng ý trước khi tạo mới.", member ? "success" : "empty");
    return member;
  }

  async function loadDashboard() {
    if (profile.role !== "manager") return;
    const dates=overviewDates();const data = await rpc("membership_dashboard", { p_from: dates.from.toISOString(), p_to: dates.to.toISOString() });
    const map = { "m-total": data.total_members, "m-new": data.new_members, "m-visits": data.visits, "m-returning": data.returning_members, "m-pending": data.pending, "m-pending-points": data.pending_points, "m-rejected": data.rejected, "m-earned": data.points_earned, "m-redeemed": data.points_redeemed, "m-rewards": data.rewards_redeemed, "m-spend": money(data.spend), "m-abnormal": data.abnormal };
    Object.keys(map).forEach(function (id) { byId(id).textContent = escapeText(map[id]); });
    await loadOverviewSeries(dates);
  }

  async function loadRewards() {
    let query = client.from("rewards").select("id,name,points_cost,voucher_value,conditions,valid_days,active").order("points_cost");
    if (profile.role !== "manager") query = query.eq("active", true);
    const result = await query;
    if (result.error) throw result.error;
    const select = byId("redeem-reward"); if (select) select.replaceChildren(new Option("Chọn phần thưởng", ""));
    const grid = byId("reward-list"); grid.replaceChildren();
    result.data.forEach(function (reward) {
      if (reward.active && select) select.add(new Option(reward.name + " — " + reward.points_cost + " điểm", reward.id));
      const card = document.createElement("article"); const title = document.createElement("strong"); const text = document.createElement("p");
      title.textContent = reward.name + " · " + reward.points_cost + " điểm" + (reward.active ? "" : " · Đã tắt"); text.textContent = reward.conditions || "Không có điều kiện bổ sung"; card.append(title, text);
      if (profile.role === "manager") { const edit=document.createElement("button");edit.className="table-action approve";edit.textContent="Sửa";edit.addEventListener("click",function(){byId("reward-id").value=reward.id;byId("reward-name").value=reward.name;byId("reward-points").value=reward.points_cost;byId("reward-value").value=reward.voucher_value==null?"":reward.voucher_value;byId("reward-days").value=reward.valid_days==null?"":reward.valid_days;byId("reward-conditions").value=reward.conditions||"";byId("reward-active").checked=reward.active;byId("reward-editor").open=true;byId("reward-editor").scrollIntoView({behavior:"smooth"});});card.appendChild(edit); }
      grid.appendChild(card);
    });
  }

  async function loadStaff() {
    if (profile.role !== "manager") return;
    const result=await client.from("program_users").select("user_id,email,display_name,role,active,can_redeem").order("display_name");if(result.error)throw result.error;const body=byId("staff-list");body.replaceChildren();result.data.forEach(function(item){const row=document.createElement("tr");row.append(cell(item.display_name),cell(staffUsername(item.email)||"—"),cell(item.role==="manager"?"Admin":"Nhân viên"),cell(item.can_redeem?"Có":"Không"),cell(item.active?"Hoạt động":"Đã khóa"));const actions=document.createElement("td");const edit=document.createElement("button");edit.className="table-action approve";edit.textContent="Sửa";edit.addEventListener("click",function(){byId("staff-email").value=staffUsername(item.email)||"";byId("staff-name").value=item.display_name;byId("staff-role").value=item.role;byId("staff-redeem").checked=item.can_redeem;byId("staff-active").checked=item.active;});actions.appendChild(edit);row.appendChild(actions);body.appendChild(row);});
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

  async function loadMembers(page) {
    if (profile.role !== "manager") return; pages.members = page || pages.members;
    const status = byId("member-list-status").value; const type = byId("member-list-type").value;
    const data = await rpc("admin_member_list", { p_search: byId("member-list-search").value.trim() || null, p_active: status ? status === "active" : null, p_from: dateStart("member-list-from"), p_to: dateEnd("member-list-to"), p_min_points: byId("member-min-points").value ? Number(byId("member-min-points").value) : null, p_max_points: byId("member-max-points").value ? Number(byId("member-max-points").value) : null, p_returning: type ? type === "returning" : null, p_page: pages.members, p_page_size: pageSize });
    const body = byId("member-list"); body.replaceChildren(); byId("member-list-empty").hidden = data.rows.length > 0;
    data.rows.forEach(function (item) {
      const row = document.createElement("tr"); row.append(cell(item.member_code),cell(item.display_name || "Chưa cập nhật"),cell(item.masked_phone),cell(item.available_points + " (chờ " + item.pending_points + ")"),cell(item.visit_count),cell(money(item.total_spend)));
      const state = document.createElement("td"); const pill = document.createElement("span"); pill.className = "status-pill " + (item.active ? "status-pill--success" : "status-pill--danger"); pill.textContent = item.active ? "Hoạt động" : "Đã khóa"; state.appendChild(pill); row.appendChild(state);
      const actions = document.createElement("td"); const view = document.createElement("button"); view.className = "table-action approve"; view.textContent = "Chi tiết"; view.addEventListener("click", function () { openMemberDetail(item.id); }); actions.appendChild(view); row.appendChild(actions); body.appendChild(row);
    });
    renderPagination("member-pagination",data,function(next){loadMembers(next);});
  }

  function detailTable(title, headers, rows) {
    const section = document.createElement("section"); section.className = "detail-section"; const heading = document.createElement("h3"); heading.textContent = title; section.appendChild(heading);
    if (!rows.length) { const empty = document.createElement("p"); empty.textContent = "Chưa có dữ liệu."; section.appendChild(empty); return section; }
    const table = document.createElement("table"); const thead = document.createElement("thead"); const trh = document.createElement("tr"); headers.forEach(function(h){const th=document.createElement("th");th.textContent=h;trh.appendChild(th);});thead.appendChild(trh);const tbody=document.createElement("tbody");
    rows.forEach(function(values){const tr=document.createElement("tr");values.forEach(function(v){tr.appendChild(cell(v));});tbody.appendChild(tr);});table.append(thead,tbody);section.appendChild(table);return section;
  }

  async function openMemberDetail(id) {
    try {
      const data = await rpc("admin_member_detail", { p_member_id: id }); const content = byId("member-detail-content"); content.replaceChildren(); byId("member-detail-title").textContent = data.member_code;
      const grid = document.createElement("div"); grid.className = "detail-grid"; [["Tên",data.display_name||"Chưa cập nhật"],["Điện thoại",data.masked_phone],["Điểm khả dụng",data.available_points],["Điểm chờ",data.pending_points],["Lượt chơi",data.visit_count],["Trạng thái",data.active?"Hoạt động":"Đã khóa"]].forEach(function(item){const a=document.createElement("article");const s=document.createElement("span");const b=document.createElement("strong");s.textContent=item[0];b.textContent=item[1];a.append(s,b);grid.appendChild(a);});content.appendChild(grid);
      content.appendChild(detailTable("Lịch sử ghé chơi",["Hóa đơn","Thời gian","Số tiền","Điểm","Trạng thái"],data.visits.map(function(v){return[v.invoice_code,formatDate(v.occurred_at),money(v.eligible_amount),v.points,v.status];})));
      content.appendChild(detailTable("Lịch sử điểm",["Loại","Biến động","Số dư","Lý do","Thời gian"],data.ledger.map(function(v){return[v.type,v.points_delta,v.balance_after,v.reason,formatDate(v.created_at)];})));
      content.appendChild(detailTable("Quà đã đổi",["Phần thưởng","Điểm","Xác minh","Nhân viên","Thời gian"],data.redemptions.map(function(v){return[v.reward_name,v.points_spent,v.verification_method,v.staff_name,formatDate(v.redeemed_at)];})));
      const actions=document.createElement("div");actions.className="detail-actions";const edit=document.createElement("button");const toggle=document.createElement("button");const anonymize=document.createElement("button");edit.className="admin-button";toggle.className="admin-button admin-button--ghost";anonymize.className="table-action";edit.textContent="Sửa tên";toggle.textContent=data.active?"Khóa tài khoản":"Mở khóa";anonymize.textContent="Ẩn danh dữ liệu";
      edit.addEventListener("click",async function(){const name=prompt("Tên hiển thị mới:",data.display_name||"");if(name===null)return;const reason=prompt("Lý do thay đổi:");if(!reason)return;await updateMember(id,name,data.active,reason);});
      toggle.addEventListener("click",async function(){const reason=prompt(data.active?"Lý do khóa tài khoản:":"Lý do mở khóa:");if(!reason)return;if(!confirm("Xác nhận thay đổi trạng thái thành viên?"))return;await updateMember(id,data.display_name,!data.active,reason);});
      anonymize.addEventListener("click",async function(){const reason=prompt("Nhập lý do ẩn danh dữ liệu (tối thiểu 10 ký tự):");if(!reason||!confirm("Ẩn danh sẽ xóa thông tin cá nhân và không thể hoàn tác. Tiếp tục?"))return;try{await rpc("admin_anonymize_member",{p_member_id:id,p_reason:reason});byId("member-detail-dialog").close();notice("Đã ẩn danh thành viên.","success");loadMembers(1);}catch(error){notice(error.message,"error");}});
      const verify=document.createElement("button");verify.className="admin-button admin-button--ghost";verify.textContent=data.phone_verified_at?"Đã xác minh SĐT":"Xác minh SĐT";verify.disabled=Boolean(data.phone_verified_at);verify.addEventListener("click",async function(){const method=prompt("Phương thức xác minh:","OTP thủ công");const note=prompt("Ghi chú xác minh:");if(!method||!note)return;try{await rpc("verify_member_phone",{p_member_id:id,p_method:method,p_note:note});notice("Đã xác minh số điện thoại.","success");openMemberDetail(id);}catch(error){notice(error.message,"error");}});
      const changePhone=document.createElement("button");changePhone.className="admin-button admin-button--ghost";changePhone.textContent="Đổi SĐT";changePhone.addEventListener("click",async function(){const phone=prompt("Số điện thoại mới:");const method=prompt("Phương thức xác minh quyền sở hữu:","OTP thủ công");const note=prompt("Ghi chú/bằng chứng xác minh:");if(!phone||!method||!note||!confirm("Xác nhận đổi số điện thoại thành viên?"))return;try{await rpc("admin_change_member_phone",{p_member_id:id,p_new_phone:phone,p_method:method,p_note:note});notice("Đã đổi và xác minh số điện thoại.","success");openMemberDetail(id);}catch(error){notice(error.message,"error");}});actions.append(edit,toggle,verify,changePhone,anonymize);content.appendChild(actions);byId("member-detail-dialog").showModal();
    } catch (error) { notice(error.message,"error"); }
  }

  async function updateMember(id,name,active,reason){try{await rpc("admin_update_member",{p_member_id:id,p_display_name:name,p_active:active,p_reason:reason});byId("member-detail-dialog").close();notice("Đã cập nhật thành viên.","success");await loadMembers(pages.members);}catch(error){notice(error.message,"error");}}

  async function loadEarns(page) {
    pages.earns=page||pages.earns;const data=await rpc("earn_request_list",{p_status:byId("earn-list-status").value||null,p_search:byId("earn-list-search").value.trim()||null,p_from:dateStart("earn-list-from"),p_to:dateEnd("earn-list-to"),p_page:pages.earns,p_page_size:pageSize});const body=byId("earn-list");body.replaceChildren();byId("earn-list-empty").hidden=data.rows.length>0;
    data.rows.forEach(function(item){const row=document.createElement("tr");row.append(cell(item.invoice_code),cell(item.member_code+"\n"+(item.display_name||"")),cell(money(item.eligible_amount)),cell(item.points+(item.abnormal?" ⚠":"")),cell(formatDate(item.occurred_at)),cell(item.submitted_by_name));const st=document.createElement("td");st.appendChild(statusLabel(item.status));row.appendChild(st);const actions=document.createElement("td");if(item.status==="pending"){const cancel=document.createElement("button");cancel.className="table-action";cancel.textContent="Hủy";cancel.addEventListener("click",function(){cancelEarn(item.id);});actions.appendChild(cancel);}row.appendChild(actions);body.appendChild(row);});renderPagination("earn-pagination",data,function(next){loadEarns(next);});
  }
  async function cancelEarn(id){const reason=prompt("Lý do hủy yêu cầu:");if(!reason||!confirm("Xác nhận hủy yêu cầu đang chờ?"))return;try{await rpc("cancel_earn_request",{p_request_id:id,p_reason:reason});notice("Đã hủy yêu cầu.","success");await Promise.all([loadEarns(pages.earns),loadPending(),loadDashboard()]);}catch(error){notice(error.message,"error");}}

  async function loadRedemptions(page){pages.redemptions=page||pages.redemptions;const data=await rpc("redemption_list",{p_search:byId("redemption-search").value.trim()||null,p_from:dateStart("redemption-from"),p_to:dateEnd("redemption-to"),p_page:pages.redemptions,p_page_size:pageSize});const body=byId("redemption-list");body.replaceChildren();byId("redemption-empty").hidden=data.rows.length>0;data.rows.forEach(function(item){const row=document.createElement("tr");row.append(cell(item.member_code+"\n"+(item.display_name||"")),cell(item.reward_name),cell(item.points_spent),cell(item.verification_method),cell(item.redeemed_by_name),cell(formatDate(item.redeemed_at)));body.appendChild(row);});renderPagination("redemption-pagination",data,function(next){loadRedemptions(next);});}

  async function loadActivity(page){if(profile.role!=="manager")return;pages.activity=page||pages.activity;const data=await rpc("admin_activity_list",{p_search:byId("activity-search").value.trim()||null,p_page:pages.activity,p_page_size:pageSize});const body=byId("activity-list");body.replaceChildren();byId("activity-empty").hidden=data.rows.length>0;data.rows.forEach(function(item){const row=document.createElement("tr");row.append(cell(formatDate(item.created_at)),cell(item.actor_name||"Hệ thống"),cell(item.action),cell(item.entity_type+" "+(item.entity_id||"")),cell(JSON.stringify(item.details||{})));body.appendChild(row);});renderPagination("activity-pagination",data,function(next){loadActivity(next);});}

  async function review(id, approve) {
    const reason = window.prompt(approve ? "Ghi chú đối soát (tùy chọn):" : "Lý do từ chối:");
    if (reason === null || (!approve && !reason.trim())) return;
    if (!window.confirm(approve ? "Xác nhận hóa đơn hợp lệ và cộng điểm?" : "Xác nhận từ chối yêu cầu?")) return;
    try { await rpc("review_earn_request", { p_request_id: id, p_approve: approve, p_reason: reason }); notice("Đã xử lý yêu cầu.", "success"); await Promise.all([loadPending(), loadEarns(pages.earns), loadDashboard()]); } catch (error) { notice(error.message, "error"); }
  }

  function bindForms() {
    byId("member-lookup-form").addEventListener("submit", async function (event) { event.preventDefault(); try { notice("", ""); await lookup(byId("member-phone").value); } catch (error) { lookupStatus(error.message, "error"); notice(error.message, "error"); } });
    byId("member-create-form").addEventListener("submit", async function (event) { event.preventDefault(); try { const rows = await rpc("create_member", { p_phone: byId("member-phone").value, p_name: byId("member-name").value, p_membership_consent: byId("member-consent").checked, p_marketing_consent: byId("marketing-consent").checked, p_policy_version: "2026-11" }); renderMember(rows[0]); byId("member-create-box").hidden = true; await issueMemberPassword(rows[0],false);notice("Đã tạo thành viên và tài khoản đăng nhập.", "success"); } catch (error) { notice(error.message, "error"); } });
    byId("earn-form").addEventListener("submit", async function (event) { event.preventDefault(); if (!currentMember) return notice("Hãy tra cứu thành viên trước.", "error"); if (!window.confirm("Gửi yêu cầu tích điểm để quản lý đối soát?")) return; try { await rpc("submit_earn_request", { p_member_id: currentMember.id, p_invoice_code: byId("earn-invoice").value, p_paid_amount: Number(byId("earn-paid").value), p_eligible_amount: Number(byId("earn-eligible").value), p_occurred_at: new Date(byId("earn-time").value).toISOString(), p_room_type: byId("earn-room").value, p_applied_program: byId("earn-program").value || null }); notice("Đã gửi yêu cầu, điểm đang chờ quản lý duyệt.", "success"); event.target.reset(); byId("earn-member-code").value = currentMember.member_code; await Promise.all([lookup(byId("member-phone").value),loadEarns(1)]); } catch (error) { notice(error.message, "error"); } });
    byId("redeem-code-form").addEventListener("submit", async function (event) { event.preventDefault(); if (!window.confirm("Đã đối chiếu quà và xác nhận giao cho khách?")) return; const button=event.submitter; try { button.disabled=true; const data=await rpc("fulfill_redemption_code",{p_code:byId("redeem-code").value}); notice(data.message || ("Đã giao "+data.reward_name+" cho "+data.member_code+"."),data.expired?"error":"success");event.target.reset();await loadRedemptions(1);} catch(error){notice(error.message,"error");} finally {button.disabled=false;} });
    byId("settings-form").addEventListener("submit", async function (event) { event.preventDefault(); if (!window.confirm("Thay đổi này chỉ áp dụng cho giao dịch mới. Tiếp tục?")) return; try { await rpc("update_program_settings", { p_spend_per_point: Number(byId("setting-spend").value), p_point_expiry_months: Number(byId("setting-expiry").value), p_abnormal_invoice_amount: Number(byId("setting-abnormal").value), p_return_bonus_points: Number(byId("setting-return-points").value), p_return_within_days: Number(byId("setting-return-days").value), p_policy_version: byId("setting-policy").value }); notice("Đã lưu cấu hình chương trình.", "success"); await loadSettings(); } catch (error) { notice(error.message, "error"); } });
    byId("reward-form").addEventListener("submit", async function (event) { event.preventDefault(); try { await rpc("save_reward", { p_id: byId("reward-id").value||null, p_name: byId("reward-name").value, p_points_cost: Number(byId("reward-points").value), p_voucher_value: byId("reward-value").value ? Number(byId("reward-value").value) : null, p_conditions: byId("reward-conditions").value, p_valid_days: byId("reward-days").value ? Number(byId("reward-days").value) : null, p_active: byId("reward-active").checked }); notice("Đã lưu phần thưởng.", "success"); event.target.reset(); byId("reward-id").value="";byId("reward-active").checked = true; await loadRewards(); } catch (error) { notice(error.message, "error"); } });
    byId("staff-form").addEventListener("submit", async function (event) { event.preventDefault(); if (!window.confirm("Xác nhận thay đổi quyền tài khoản này?")) return; try { await rpc("save_staff_access", { p_email: staffLoginEmail(byId("staff-email").value), p_display_name: byId("staff-name").value, p_role: byId("staff-role").value, p_active: byId("staff-active").checked, p_can_redeem: byId("staff-redeem").checked }); notice("Đã cập nhật quyền nhân viên.", "success"); event.target.reset(); byId("staff-active").checked = true;await loadStaff(); } catch (error) { notice(error.message, "error"); } });
  }

  async function initialize(event) {
    client = event.detail.client; profile = event.detail.profile;
    byId("ops-user-name").textContent = profile.display_name || event.detail.session.user.email;
    byId("ops-user-role").textContent = profile.role === "manager" ? "Admin" : "Nhân viên";
    document.querySelectorAll("[data-manager-only]").forEach(function (node) { node.hidden = profile.role !== "manager"; });
    if (profile.role !== "manager") {
      document.querySelector('[data-panel="membership-overview"]').hidden = true;
      document.querySelector('[data-panel="member-lookup"]').textContent = "Tra cứu / Thêm thành viên";
      document.querySelector('[data-panel="earn-points"]').textContent = "Tích điểm / Lịch sử của tôi";
      if (!profile.can_redeem) document.querySelector('[data-panel="reward-redemption"]').hidden = true;
    }
    document.querySelectorAll(".ops-nav button").forEach(function (button) { button.addEventListener("click", function () { showPanel(button.dataset.panel); }); });
    window.addEventListener("hashchange", function () { showPanel(window.location.hash.slice(1)); });
    byId("membership-refresh").addEventListener("click", loadDashboard); byId("pending-refresh").addEventListener("click", loadPending);
    byId("overview-range").addEventListener("change",loadDashboard);byId("member-list-filter").addEventListener("click",function(){loadMembers(1);});byId("earn-list-filter").addEventListener("click",function(){loadEarns(1);});byId("redemption-filter").addEventListener("click",function(){loadRedemptions(1);});byId("activity-filter").addEventListener("click",function(){loadActivity(1);});
    byId("earn-time").value = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    bindForms();
    showPanel(profile.role === "manager" ? (window.location.hash.slice(1) || "membership-overview") : "member-lookup");
    try { await Promise.all([loadDashboard(), loadRewards(), loadSettings(), loadPending(), loadMembers(1), loadEarns(1), loadRedemptions(1), loadActivity(1), loadStaff()]); } catch (error) { notice("Dashboard chưa sẵn sàng: " + error.message + ". Hãy chạy đầy đủ migration Supabase mới.", "error"); }
  }

  document.addEventListener("playnest:admin-ready", initialize);
})();
