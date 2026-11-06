(function () {
  "use strict";

  function parseRating(value) {
    const rating = Number(String(value || "").replace("/5", ""));
    return Number.isInteger(rating) && rating >= 1 && rating <= 5
      ? rating
      : null;
  }

  function collectAnswers(formData) {
    const answers = {};
    const ignoredFields = new Set([
      "Nguồn gửi",
      "Trang gửi",
      "Thời gian gửi"
    ]);

    formData.forEach(function (value, originalKey) {
      if (originalKey.startsWith("_") || ignoredFields.has(originalKey)) return;

      const key = originalKey.replace(/\[\]$/, "");
      if (Object.prototype.hasOwnProperty.call(answers, key)) {
        if (!Array.isArray(answers[key])) answers[key] = [answers[key]];
        answers[key].push(value);
      } else {
        answers[key] = value;
      }
    });

    return answers;
  }

  function setSubmissionState(form, state, message) {
    const submitButton = form.querySelector('[type="submit"]');
    const status = document.getElementById("survey-storage-status");

    if (submitButton) {
      if (!submitButton.dataset.originalHtml) {
        submitButton.dataset.originalHtml = submitButton.innerHTML;
      }

      submitButton.disabled = state === "loading";
      submitButton.innerHTML = state === "loading"
        ? 'Đang gửi đánh giá <i class="fa-solid fa-spinner fa-spin"></i>'
        : submitButton.dataset.originalHtml;
    }

    if (status) {
      status.hidden = !message;
      status.textContent = message || "";
      status.dataset.state = state;
    }
  }

  function prepareSurveyStorage() {
    const form = document.getElementById("customer-survey-form");
    const config = window.playnestSupabaseConfig;
    const supabaseLibrary = window.supabase;

    if (!form) return;

    if (!config || !supabaseLibrary || typeof supabaseLibrary.createClient !== "function") {
      console.error("PlayNest: Supabase chưa được tải; form khảo sát chưa thể lưu vào database.");
      setSubmissionState(
        form,
        "error",
        "Kết nối lưu trữ chưa sẵn sàng. Vui lòng tải lại trang và thử lại."
      );
      return;
    }

    const supabaseClient = supabaseLibrary.createClient(
      config.url,
      config.publishableKey,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false
        }
      }
    );

    let isSubmitting = false;

    form.addEventListener("submit", async function (event) {
      if (event.defaultPrevented || !form.checkValidity()) return;

      event.preventDefault();
      if (isSubmitting) return;

      isSubmitting = true;
      setSubmissionState(form, "loading", "Đang lưu đánh giá của bạn...");

      const formData = new FormData(form);
      const payload = {
        form_version: "1",
        source: "playnest.vn/survey.html",
        service_rating: parseRating(
          formData.get("8. Đánh giá trải nghiệm và dịch vụ")
        ),
        food_rating: parseRating(formData.get("9. Đánh giá F&B")),
        staff_name: String(
          formData.get("10. Tên nhân viên phục vụ") || ""
        ).trim() || null,
        staff_rating: parseRating(
          formData.get("11. Đánh giá nhân viên phục vụ")
        ),
        answers: collectAnswers(formData),
        page_url: window.location.href
      };

      try {
        const result = await supabaseClient
          .from("survey_responses")
          .insert(payload);

        if (result.error) throw result.error;

        setSubmissionState(form, "success", "Đã lưu đánh giá thành công.");
        window.location.assign("survey-thank-you.html");
      } catch (error) {
        console.error("PlayNest: Không thể lưu khảo sát vào Supabase.", error);
        isSubmitting = false;
        setSubmissionState(
          form,
          "error",
          "Chưa thể lưu đánh giá. Vui lòng kiểm tra kết nối và thử lại."
        );
      }
    });
  }

  document.addEventListener("DOMContentLoaded", prepareSurveyStorage);
})();
