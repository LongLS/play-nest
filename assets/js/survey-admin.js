(function () {
  "use strict";

  const config = window.playnestSupabaseConfig;
  const library = window.supabase;

  if (!config || !library || typeof library.createClient !== "function") {
    document.addEventListener("DOMContentLoaded", function () {
      showNotice("Không thể tải kết nối Supabase. Vui lòng tải lại trang.", "error");
    });
    return;
  }

  const client = library.createClient(config.url, config.publishableKey);
  let responses = [];
  let surveyPage = 1;
  let surveyTotal = 0;
  const surveyPageSize = 15;

  function element(id) {
    return document.getElementById(id);
  }

  function staffLoginEmail(value) {
    const login = String(value || "").trim().toLowerCase();
    if (login.includes("@")) return login;
    if (!/^[a-z0-9._-]{3,40}$/.test(login)) throw new Error("Tên đăng nhập không hợp lệ.");
    return login + "@staff.playnest.vn";
  }

  function showNotice(message, state) {
    const notice = element("admin-notice");
    if (!notice) return;
    notice.textContent = message || "";
    notice.dataset.state = state || "";
    notice.hidden = !message;
  }

  function setLoading(button, loading, label) {
    if (!button) return;
    if (!button.dataset.label) button.dataset.label = button.textContent;
    button.disabled = loading;
    button.textContent = loading ? label : button.dataset.label;
  }

  function formatDate(value) {
    return new Intl.DateTimeFormat("vi-VN", {
      dateStyle: "short",
      timeStyle: "short"
    }).format(new Date(value));
  }

  function ratingText(value) {
    const rating = Number(value) || 0;
    return "★".repeat(rating) + "☆".repeat(Math.max(0, 5 - rating));
  }

  function createCell(text, className) {
    const cell = document.createElement("td");
    cell.textContent = text;
    if (className) cell.className = className;
    return cell;
  }

  function createAnswerList(answers) {
    const list = document.createElement("dl");
    list.className = "admin-answer-list";

    Object.entries(answers || {}).forEach(function (entry) {
      const wrapper = document.createElement("div");
      const term = document.createElement("dt");
      const description = document.createElement("dd");
      term.textContent = entry[0];
      description.textContent = Array.isArray(entry[1]) ? entry[1].join(", ") : String(entry[1] || "—");
      wrapper.append(term, description);
      list.appendChild(wrapper);
    });

    return list;
  }

  function filteredResponses() {
    return responses;
  }

  function surveyStatus(value) {
    const labels = { new: "Chưa xem", viewed: "Đã xem", processed: "Đã xử lý", archived: "Lưu trữ" };
    const span = document.createElement("span"); span.className = "status-pill " + (value === "processed" ? "status-pill--success" : value === "new" ? "status-pill--warning" : ""); span.textContent = labels[value] || value; return span;
  }

  function renderResponses() {
    const list = element("admin-response-list");
    const empty = element("admin-empty");
    if (!list || !empty) return;
    const items = filteredResponses();
    list.replaceChildren();

    items.forEach(function (item) {
      const row = document.createElement("tr");
      row.appendChild(createCell(String(item.id).slice(0, 8).toUpperCase()));
      row.appendChild(createCell(formatDate(item.created_at)));
      row.appendChild(createCell(ratingText(item.service_rating), "admin-stars"));
      const preview = Object.values(item.answers || {}).map(function(value){return Array.isArray(value)?value.join(", "):String(value||"");}).filter(Boolean).join(" · ");
      row.appendChild(createCell(preview.slice(0, 100) || "Không có nội dung"));
      const state = document.createElement("td"); state.appendChild(surveyStatus(item.management_status)); row.appendChild(state);
      const actions = document.createElement("td"); const view = document.createElement("button"); view.className = "table-action approve"; view.textContent = "Chi tiết"; view.addEventListener("click",function(){openSurvey(item);}); actions.appendChild(view); row.appendChild(actions);
      list.appendChild(row);
    });

    empty.hidden = items.length !== 0;
    element("admin-result-count").textContent = surveyTotal + " phản hồi";
  }

  function renderStats(summary) {
    if (!element("stat-total")) return;
    element("stat-total").textContent = String(summary.total || 0);
    element("stat-service").textContent = summary.service_avg == null ? "—" : summary.service_avg + "/5";
    element("stat-food").textContent = summary.food_avg == null ? "—" : summary.food_avg + "/5";
    element("stat-staff").textContent = summary.staff_avg == null ? "—" : summary.staff_avg + "/5";
  }

  function renderSurveyPagination(data) {
    const box = element("survey-pagination"); if (!box) return; box.replaceChildren(); const pages = Math.max(1,Math.ceil(Number(data.total||0)/data.page_size));
    const prev=document.createElement("button"),next=document.createElement("button"),label=document.createElement("span");prev.textContent="‹";next.textContent="›";label.textContent="Trang "+data.page+"/"+pages;prev.disabled=data.page<=1;next.disabled=data.page>=pages;prev.addEventListener("click",function(){loadResponses(data.page-1);});next.addEventListener("click",function(){loadResponses(data.page+1);});box.append(prev,label,next);
  }

  function openSurvey(item) {
    const content=element("survey-detail-content");content.replaceChildren();element("survey-detail-title").textContent="Khảo sát "+String(item.id).slice(0,8).toUpperCase();
    const info=document.createElement("div");info.className="detail-grid";[["Ngày gửi",formatDate(item.created_at)],["Dịch vụ",ratingText(item.service_rating)],["F&B",ratingText(item.food_rating)],["Nhân viên",ratingText(item.staff_rating)],["Tên nhân viên",item.staff_name||"Không ghi tên"],["Trạng thái",item.management_status]].forEach(function(pair){const a=document.createElement("article"),s=document.createElement("span"),b=document.createElement("strong");s.textContent=pair[0];b.textContent=pair[1];a.append(s,b);info.appendChild(a);});content.appendChild(info);
    const answers=document.createElement("section");answers.className="detail-section";const h=document.createElement("h3");h.textContent="Câu trả lời gốc";answers.append(h,createAnswerList(item.answers));content.appendChild(answers);
    const management=document.createElement("section");management.className="detail-section";const title=document.createElement("h3");title.textContent="Xử lý nội bộ";management.appendChild(title);if(item._legacy){const warning=document.createElement("p");warning.textContent="Chạy migration 20261107020000 để bật ghi chú, trạng thái xử lý và lưu trữ khảo sát.";management.appendChild(warning);}else{const select=document.createElement("select");[["new","Chưa xem"],["viewed","Đã xem"],["processed","Đã xử lý"]].forEach(function(option){select.add(new Option(option[1],option[0],false,item.management_status===option[0]));});const note=document.createElement("textarea");note.placeholder="Ghi chú nội bộ";note.value=item.internal_note||"";const actions=document.createElement("div");actions.className="detail-actions";const save=document.createElement("button");const archive=document.createElement("button");save.type="button";archive.type="button";save.className="admin-button";archive.className="table-action";save.textContent="Lưu xử lý";archive.textContent="Lưu trữ";save.addEventListener("click",async function(){try{const result=await client.rpc("admin_update_survey",{p_id:item.id,p_status:select.value,p_note:note.value});if(result.error)throw result.error;element("survey-detail-dialog").close();showNotice("Đã cập nhật khảo sát.","success");loadResponses(surveyPage);}catch(error){showNotice(error.message,"error");}});archive.addEventListener("click",async function(){const reason=prompt("Lý do lưu trữ khảo sát:");if(!reason||!confirm("Khảo sát sẽ bị ẩn khỏi danh sách. Tiếp tục?"))return;const result=await client.rpc("admin_archive_survey",{p_id:item.id,p_reason:reason});if(result.error)return showNotice(result.error.message,"error");element("survey-detail-dialog").close();showNotice("Đã lưu trữ khảo sát.","success");loadResponses(surveyPage);});actions.append(save,archive);management.append(select,note,actions);}content.appendChild(management);element("survey-detail-dialog").showModal();
  }

  async function verifyAdmin(user) {
    const membership = await client.from("program_users").select("user_id, display_name, role, can_redeem, must_change_password").eq("user_id", user.id).eq("active", true).maybeSingle();
    if (!membership.error && membership.data) return membership.data;
    const legacy = await client.from("admin_users").select("user_id").eq("user_id", user.id).maybeSingle();
    if (legacy.error) throw legacy.error;
    return legacy.data ? { user_id: user.id, display_name: user.email, role: "manager", can_redeem: true } : null;
  }

  async function loadResponses(page) {
    if (!element("admin-response-list")) return;
    surveyPage = page || surveyPage;
    const refresh = element("admin-refresh");
    setLoading(refresh, true, "Đang tải...");
    showNotice("", "");

    let data;
    try { data = await fetchSurveyPage(surveyPage, surveyPageSize); }
    catch (error) { setLoading(refresh, false); showNotice("Không thể tải dữ liệu khảo sát: " + error.message, "error"); return; }
    setLoading(refresh, false);
    responses = data.rows || []; surveyTotal = Number(data.total || 0);
    renderStats(data.summary || {});
    renderResponses();
    renderSurveyPagination(data);
    if (data.legacy) showNotice("Đang dùng chế độ tương thích. Hãy chạy migration 20261107020000 để bật trạng thái xử lý, lưu trữ và phân trang phía máy chủ.", "error");
    element("admin-updated-at").textContent = "Cập nhật lúc " + new Date().toLocaleString("vi-VN");
  }

  async function showDashboard(session) {
    try {
      const profile = await verifyAdmin(session.user);
      if (!profile) {
        await client.auth.signOut();
        showNotice("Tài khoản này chưa được cấp quyền quản trị khảo sát.", "error");
        showLogin();
        return;
      }

      if (profile.must_change_password) {
        showPasswordChange();
        return;
      }

      element("admin-login-section").hidden = true;
      element("staff-password-section").hidden = true;
      element("admin-dashboard").hidden = false;
      element("admin-logout").hidden = false;
      window.playnestAdmin = { client: client, session: session, profile: profile };
      document.dispatchEvent(new CustomEvent("playnest:admin-ready", { detail: window.playnestAdmin }));
      if (profile.role === "manager" && element("admin-response-list")) await loadResponses();
    } catch (error) {
      showNotice("Không thể xác minh quyền quản trị: " + error.message, "error");
      showLogin();
    }
  }

  function showLogin() {
    element("admin-login-section").hidden = false;
    element("staff-password-section").hidden = true;
    element("admin-dashboard").hidden = true;
    element("admin-logout").hidden = true;
  }

  function showPasswordChange() {
    element("admin-login-section").hidden = true;
    element("staff-password-section").hidden = false;
    element("admin-dashboard").hidden = true;
    element("admin-logout").hidden = false;
    element("staff-new-password").focus();
  }

  function csvEscape(value) {
    const text = String(value == null ? "" : value);
    return '"' + text.replace(/"/g, '""') + '"';
  }

  function surveyFilters(page, pageSize) {
    const from = element("survey-from").value;
    const to = element("survey-to").value;
    let toValue = null;
    if (to) { const date = new Date(to + "T00:00:00"); date.setDate(date.getDate() + 1); toValue = date.toISOString(); }
    return { p_search: element("admin-search").value.trim() || null, p_rating: element("admin-rating-filter").value ? Number(element("admin-rating-filter").value) : null, p_status: element("survey-status-filter").value || null, p_from: from ? new Date(from + "T00:00:00").toISOString() : null, p_to: toValue, p_page: page, p_page_size: pageSize };
  }

  function isMissingSurveyRpc(error) {
    return error && (error.code === "PGRST202" || /admin_survey_list|schema cache/i.test(error.message || ""));
  }

  async function legacySurveyList(page, pageSize) {
    const result = await client.from("survey_responses").select("*").order("created_at", { ascending: false }).limit(1000);
    if (result.error) throw result.error;
    const filters = surveyFilters(page, pageSize);
    let rows = (result.data || []).map(function (item) {
      return Object.assign({ management_status: "new", internal_note: "", _legacy: true }, item);
    });
    rows = rows.filter(function (item) {
      const haystack = [item.staff_name, JSON.stringify(item.answers || {})].join(" ").toLowerCase();
      if (filters.p_search && !haystack.includes(filters.p_search.toLowerCase())) return false;
      if (filters.p_rating && Number(item.service_rating) !== filters.p_rating && Number(item.food_rating) !== filters.p_rating && Number(item.staff_rating) !== filters.p_rating) return false;
      if (filters.p_status && item.management_status !== filters.p_status) return false;
      if (filters.p_from && new Date(item.created_at) < new Date(filters.p_from)) return false;
      if (filters.p_to && new Date(item.created_at) >= new Date(filters.p_to)) return false;
      return true;
    });
    const total = rows.length;
    const average = function (key) { const values=rows.map(function(x){return Number(x[key]);}).filter(Boolean);return values.length ? Math.round(values.reduce(function(a,b){return a+b;},0)/values.length*10)/10 : null; };
    return { rows: rows.slice((page-1)*pageSize,page*pageSize), total: total, page: page, page_size: pageSize, summary: { total: total, service_avg: average("service_rating"), food_avg: average("food_rating"), staff_avg: average("staff_rating") }, legacy: true };
  }

  async function fetchSurveyPage(page, pageSize) {
    const result = await client.rpc("admin_survey_list", surveyFilters(page, pageSize));
    if (!result.error) return result.data;
    if (!isMissingSurveyRpc(result.error)) throw result.error;
    return legacySurveyList(page, pageSize);
  }

  async function exportCsv() {
    const button = element("admin-export"); setLoading(button, true, "Đang xuất...");
    let exportRows = []; let page = 1; let total = 0;
    do {
      let data;
      try { data = await fetchSurveyPage(page, 100); }
      catch (error) { setLoading(button, false); showNotice(error.message, "error"); return; }
      exportRows = exportRows.concat(data.rows || []); total = Number(data.total || 0); page += 1;
    } while (exportRows.length < total && exportRows.length < 5000);
    const columns = ["Thời gian", "Dịch vụ", "F&B", "Tên nhân viên", "Đánh giá nhân viên", "Chi tiết"];
    const rows = exportRows.map(function (item) {
      return [
        formatDate(item.created_at),
        item.service_rating,
        item.food_rating,
        item.staff_name || "",
        item.staff_rating,
        JSON.stringify(item.answers || {})
      ];
    });
    const csv = "\uFEFF" + [columns].concat(rows).map(function (row) {
      return row.map(csvEscape).join(",");
    }).join("\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = "playnest-survey-" + new Date().toISOString().slice(0, 10) + ".csv";
    link.click();
    URL.revokeObjectURL(url);
    setLoading(button, false);
  }

  async function initialize() {
    const sessionResult = await client.auth.getSession();
    if (sessionResult.data.session) {
      await showDashboard(sessionResult.data.session);
    } else {
      showLogin();
    }

    element("admin-login-form").addEventListener("submit", async function (event) {
      event.preventDefault();
      const button = event.currentTarget.querySelector('[type="submit"]');
      setLoading(button, true, "Đang đăng nhập...");
      showNotice("", "");

      let email;
      try { email = staffLoginEmail(element("admin-email").value); }
      catch (error) { setLoading(button, false); showNotice(error.message, "error"); return; }
      const result = await client.auth.signInWithPassword({ email: email, password: element("admin-password").value });

      setLoading(button, false);
      if (result.error) {
        showNotice("Đăng nhập không thành công. Kiểm tra lại tên đăng nhập và mật khẩu.", "error");
        return;
      }
      await showDashboard(result.data.session);
    });

    element("staff-password-form").addEventListener("submit", async function (event) {
      event.preventDefault();
      const password=element("staff-new-password").value,confirmation=element("staff-confirm-password").value;
      if(password.length<8){showNotice("Mật khẩu mới phải có ít nhất 8 ký tự.","error");return;}
      if(password!==confirmation){showNotice("Hai lần nhập mật khẩu mới chưa khớp.","error");return;}
      const button=event.currentTarget.querySelector('[type="submit"]');setLoading(button,true,"Đang đổi...");showNotice("","");
      const updateResult=await client.auth.updateUser({password:password});
      if(updateResult.error){setLoading(button,false);showNotice("Không thể đổi mật khẩu: "+updateResult.error.message,"error");return;}
      const changed=await client.rpc("staff_password_changed");
      setLoading(button,false);
      if(changed.error){showNotice("Mật khẩu đã đổi nhưng chưa thể hoàn tất xác nhận: "+changed.error.message,"error");return;}
      event.currentTarget.reset();showNotice("Đã đổi mật khẩu thành công.","success");
      const current=await client.auth.getSession();if(current.data.session)await showDashboard(current.data.session);
    });

    element("admin-logout").addEventListener("click", async function () {
      await client.auth.signOut();
      responses = [];
      showLogin();
      showNotice("Đã đăng xuất khỏi trang quản trị.", "success");
    });
    if (element("admin-refresh")) element("admin-refresh").addEventListener("click", loadResponses);
    if (element("admin-export")) element("admin-export").addEventListener("click", exportCsv);
    if (element("admin-search")) element("admin-search").addEventListener("change", function(){loadResponses(1);});
    if (element("admin-rating-filter")) element("admin-rating-filter").addEventListener("change", function(){loadResponses(1);});
    if (element("survey-status-filter")) element("survey-status-filter").addEventListener("change", function(){loadResponses(1);});
    if (element("survey-from")) element("survey-from").addEventListener("change", function(){loadResponses(1);});
    if (element("survey-to")) element("survey-to").addEventListener("change", function(){loadResponses(1);});
  }

  document.addEventListener("DOMContentLoaded", initialize);
})();
