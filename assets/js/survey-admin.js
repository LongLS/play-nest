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

  function element(id) {
    return document.getElementById(id);
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

  function average(key) {
    if (!responses.length) return "—";
    const values = responses.map(function (item) { return Number(item[key]); }).filter(Number.isFinite);
    if (!values.length) return "—";
    return (values.reduce(function (sum, value) { return sum + value; }, 0) / values.length).toFixed(1) + "/5";
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

  function createDetails(answers) {
    const details = document.createElement("details");
    details.className = "admin-details";
    const summary = document.createElement("summary");
    summary.textContent = "Xem phản hồi";
    details.appendChild(summary);

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

    details.appendChild(list);
    return details;
  }

  function filteredResponses() {
    const query = element("admin-search").value.trim().toLocaleLowerCase("vi");
    const rating = element("admin-rating-filter").value;

    return responses.filter(function (item) {
      const matchesRating = !rating || String(item.service_rating) === rating;
      const searchable = [item.staff_name || "", JSON.stringify(item.answers || {})]
        .join(" ")
        .toLocaleLowerCase("vi");
      return matchesRating && (!query || searchable.includes(query));
    });
  }

  function renderResponses() {
    const list = element("admin-response-list");
    const empty = element("admin-empty");
    const items = filteredResponses();
    list.replaceChildren();

    items.forEach(function (item) {
      const row = document.createElement("tr");
      row.appendChild(createCell(formatDate(item.created_at)));
      row.appendChild(createCell(ratingText(item.service_rating), "admin-stars"));
      row.appendChild(createCell(ratingText(item.food_rating), "admin-stars"));
      row.appendChild(createCell(ratingText(item.staff_rating), "admin-stars"));
      row.appendChild(createCell(item.staff_name || "Không ghi tên"));
      const detailsCell = document.createElement("td");
      detailsCell.appendChild(createDetails(item.answers));
      row.appendChild(detailsCell);
      list.appendChild(row);
    });

    empty.hidden = items.length !== 0;
    element("admin-result-count").textContent = items.length + " phản hồi";
  }

  function renderStats() {
    element("stat-total").textContent = String(responses.length);
    element("stat-service").textContent = average("service_rating");
    element("stat-food").textContent = average("food_rating");
    element("stat-staff").textContent = average("staff_rating");
  }

  async function verifyAdmin(user) {
    const result = await client
      .from("admin_users")
      .select("user_id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (result.error) throw result.error;
    return Boolean(result.data);
  }

  async function loadResponses() {
    const refresh = element("admin-refresh");
    setLoading(refresh, true, "Đang tải...");
    showNotice("", "");

    const result = await client
      .from("survey_responses")
      .select("id, created_at, service_rating, food_rating, staff_name, staff_rating, answers")
      .order("created_at", { ascending: false })
      .limit(500);

    setLoading(refresh, false);
    if (result.error) {
      showNotice("Không thể tải dữ liệu khảo sát: " + result.error.message, "error");
      return;
    }

    responses = result.data || [];
    renderStats();
    renderResponses();
    element("admin-updated-at").textContent = "Cập nhật lúc " + new Date().toLocaleString("vi-VN");
  }

  async function showDashboard(session) {
    try {
      const allowed = await verifyAdmin(session.user);
      if (!allowed) {
        await client.auth.signOut();
        showNotice("Tài khoản này chưa được cấp quyền quản trị khảo sát.", "error");
        showLogin();
        return;
      }

      element("admin-login-section").hidden = true;
      element("admin-dashboard").hidden = false;
      element("admin-logout").hidden = false;
      await loadResponses();
    } catch (error) {
      showNotice("Không thể xác minh quyền quản trị: " + error.message, "error");
      showLogin();
    }
  }

  function showLogin() {
    element("admin-login-section").hidden = false;
    element("admin-dashboard").hidden = true;
    element("admin-logout").hidden = true;
  }

  function csvEscape(value) {
    const text = String(value == null ? "" : value);
    return '"' + text.replace(/"/g, '""') + '"';
  }

  function exportCsv() {
    const columns = ["Thời gian", "Dịch vụ", "F&B", "Tên nhân viên", "Đánh giá nhân viên", "Chi tiết"];
    const rows = filteredResponses().map(function (item) {
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

      const result = await client.auth.signInWithPassword({
        email: element("admin-email").value.trim(),
        password: element("admin-password").value
      });

      setLoading(button, false);
      if (result.error) {
        showNotice("Đăng nhập không thành công. Kiểm tra lại email và mật khẩu.", "error");
        return;
      }
      await showDashboard(result.data.session);
    });

    element("admin-logout").addEventListener("click", async function () {
      await client.auth.signOut();
      responses = [];
      showLogin();
      showNotice("Đã đăng xuất khỏi trang quản trị.", "success");
    });
    element("admin-refresh").addEventListener("click", loadResponses);
    element("admin-export").addEventListener("click", exportCsv);
    element("admin-search").addEventListener("input", renderResponses);
    element("admin-rating-filter").addEventListener("change", renderResponses);
  }

  document.addEventListener("DOMContentLoaded", initialize);
})();
