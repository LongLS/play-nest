(function(){
  'use strict';
  var KEY='playnest-language';
  var params=new URLSearchParams(location.search);
  var requested=params.get('lang');
  if(/^\/en(?:\/|$)/.test(location.pathname)){location.replace('/?lang=en');return;}
  function getLanguage(){
    if(requested==='vi'||requested==='en'){try{localStorage.setItem(KEY,requested);}catch(e){}return requested;}
    try{var saved=localStorage.getItem(KEY);if(saved==='vi'||saved==='en')return saved;}catch(e){}
    var list=navigator.languages&&navigator.languages.length?navigator.languages:[navigator.language||'vi'];
    return list.some(function(x){return String(x).toLowerCase().indexOf('vi')===0;})?'vi':'en';
  }
  var language=getLanguage();
  if(language==='en')document.documentElement.style.visibility='hidden';
  var en={
    'Game Box Hà Nội | PS5 & Nintendo phòng riêng – PlayNest':'Private Gaming Lounge in Hanoi | PlayNest',
    'PlayNest là không gian gaming riêng tư dành cho cặp đôi và hội bạn với PS5, Nintendo và Netflix.':'PlayNest is a private gaming lounge for couples and groups, with PS5, Nintendo Switch and Netflix.',
    'Liên hệ PlayNest':'Contact PlayNest','Danh sách game':'Games','Bài viết':'Blog','Khảo sát khách hàng':'Customer survey','Thông tin liên hệ':'Contact','Đặt phòng ngay':'Book a room','Đăng nhập':'Sign in',
    'Phòng game riêng tư cho cặp đôi, gia đình':'Private gaming rooms for couples, families','và hội bạn tại 146 Trần Bình.':'and groups at 146 Tran Binh Street.',
    'Liên hệ đặt phòng':'Book a room','Liên hệ Zalo':'Message on Zalo','Private Gaming Lounge Hà Nội':'Private Gaming Lounge Hanoi',
    'Phòng game riêng tư cho cặp đôi, gia đình và hội bạn tại 146 Trần Bình.':'Private gaming rooms for couples, families and groups at 146 Tran Binh Street.','Xem thêm':'Learn more',
    'Mới tại PlayNest · PS5':'New at PlayNest · PS5','Chơi GTA 6 trong phòng game riêng tại Hà Nội':'Play GTA 6 in a private gaming room in Hanoi',
    'Khám phá Vice City trên màn hình lớn tại 146 Trần Bình. Liên hệ trước để kiểm tra phòng PS5 và tình trạng game.':'Explore Vice City on a large screen at 146 Tran Binh Street. Contact us first to check PS5 room availability and game status.',
    'Xem GTA 6':'Explore GTA 6','Kiểm tra phòng trống':'Check availability','Về PlayNest':'About PlayNest','Không gian riêng cho mọi cuộc vui':'Your own space for every occasion',
    'PlayNest là phòng giải trí riêng tư dành cho cặp đôi và hội bạn, kết hợp game console, phim ảnh và không gian thư giãn trong cùng một trải nghiệm.':'PlayNest is a private entertainment room for couples and groups, combining console games, movies and a comfortable place to relax.',
    'PS5 hiện đại':'Modern PS5 setup','Chơi những tựa game hấp dẫn với hình ảnh sắc nét và tay cầm chất lượng.':'Enjoy exciting games with sharp visuals and quality controllers.',
    'Nintendo vui nhộn':'Fun Nintendo games','Lựa chọn lý tưởng cho couple, gia đình và nhóm bạn cùng tranh tài.':'A great choice for couples, families and friends to play together.',
    'Netflix & điện ảnh':'Netflix & movies','Thưởng thức phim yêu thích trong không gian riêng tư và thoải mái.':'Watch your favourite movies in a comfortable private room.',
    'Phòng riêng trọn vẹn':'A fully private room','Sofa êm, âm thanh sống động và không gian chỉ dành riêng cho bạn.':'Comfortable sofas, immersive sound and a room reserved just for you.',
    'Phòng game riêng tư':'Private gaming rooms','Netflix & xem phim':'Netflix & movies','Sinh nhật & hẹn hò':'Birthdays & dates','Combo & overnight':'Combos & overnight sessions',
    'Kho game chọn lọc':'Curated game library','Game hay tại PlayNest':'Popular games at PlayNest','Xem tất cả game':'View all games','Phiêu lưu':'Adventure','Đồng đội':'Co-op','Thể thao':'Sports','Đối kháng':'Fighting','Gia đình':'Family',
    'Cùng phối hợp vượt thử thách trong tựa game dành riêng cho hai người.':'Work together through challenges in a game designed for two players.',
    'Cuộc phiêu lưu co-op đầy bất ngờ dành cho cặp đôi và bạn thân.':'A surprising co-op adventure for couples and close friends.',
    'Cùng hội bạn vào bếp, phối hợp thật nhanh và tạo nên những màn cười hết cỡ.':'Jump into the kitchen with friends for fast teamwork and plenty of laughs.',
    'So tài bóng đá cùng bạn bè trên màn hình lớn và hệ thống âm thanh sống động.':'Compete with friends on a large screen with immersive sound.',
    'Những màn đối đầu kịch tính cho người thích cạnh tranh và chinh phục.':'Intense matches for players who enjoy competition.',
    'Bộ sưu tập trò chơi vui nhộn, dễ chơi và phù hợp với mọi thành viên.':'A collection of fun, easy-to-learn games for everyone.',
    'Game Box Hà Nội riêng tư với PS5 và Nintendo':'Private Game Box in Hanoi with PS5 and Nintendo','PlayNest là':'PlayNest is a','private gaming lounge tại Hà Nội':'private gaming lounge in Hanoi',
    ', mang đến phòng game riêng tư thay cho không gian quán net đông người. Mỗi phòng phù hợp để hẹn hò, tụ tập hội bạn hoặc vui chơi cùng gia đình với PS5, Nintendo Switch và Netflix.':', offering private rooms away from crowded internet cafés. Each room is suitable for dates, groups and families, with PS5, Nintendo Switch and Netflix.',
    'Bạn có thể xem trước':'You can browse the','danh sách game PS5 và Nintendo tại PlayNest':'PS5 and Nintendo game list at PlayNest',', lọc theo thể loại và số người chơi, sau đó':', filter by genre and number of players, then','liên hệ đặt phòng game box Hà Nội':'contact us to book a private gaming room','tại 146 Phố Trần Bình, Nam Từ Liêm.':'at 146 Tran Binh Street, Nam Tu Liem.',
    'Chơi PS5 tại Hà Nội':'Play PS5 in Hanoi','Game co-op, thể thao, đối kháng và phiêu lưu trên màn hình lớn trong phòng riêng.':'Co-op, sports, fighting and adventure games on a large screen in a private room.',
    'Chơi Nintendo tại Hà Nội':'Play Nintendo in Hanoi','Mario Kart, Nintendo Switch Sports và nhiều game party dễ chơi cho nhóm bạn, gia đình.':'Mario Kart, Nintendo Switch Sports and easy party games for friends and families.',
    'Không gian kín đáo, thoải mái và chủ động cho buổi hẹn hò hoặc cuộc vui của riêng nhóm.':'A comfortable private space for dates and group activities.',
    'Câu hỏi về Game Box PlayNest':'Frequently asked questions','Game Box Hà Nội tại PlayNest có gì?':'What does PlayNest Game Box offer?',
    'PlayNest có phòng game riêng tư với PS5, Nintendo Switch, Netflix, màn hình lớn và không gian dành cho cặp đôi, gia đình hoặc hội bạn.':'PlayNest offers private rooms with PS5, Nintendo Switch, Netflix and large screens for couples, families and groups.',
    'PlayNest có game PS5 và Nintendo cho nhiều người chơi không?':'Does PlayNest have multiplayer PS5 and Nintendo games?',
    'Có. Kho game gồm game co-op, party, thể thao, đua xe và nhiều lựa chọn dễ làm quen. Bạn có thể lọc trước theo số người chơi tại trang danh sách game.':'Yes. Our library includes co-op, party, sports, racing and beginner-friendly games. You can filter by number of players.',
    'Private Gaming Lounge PlayNest ở đâu tại Hà Nội?':'Where is PlayNest Private Gaming Lounge in Hanoi?','PlayNest nằm tại 146 Phố Trần Bình, Nam Từ Liêm, Hà Nội.':'PlayNest is at 146 Tran Binh Street, Nam Tu Liem, Hanoi.',
    'Đặt phòng game PlayNest như thế nào?':'How do I book a room at PlayNest?','Liên hệ Zalo hoặc hotline':'Message us on Zalo or call','để kiểm tra lịch trống, chọn phòng và nhận tư vấn game phù hợp.':'to check availability, choose a room and get game recommendations.',
    'Khách hàng chia sẻ':'Customer stories','Những trải nghiệm đáng nhớ':'Memorable experiences','Đánh giá 5 sao trên Google':'5-star review on Google','Mình đã có trải nghiệm rất tốt ở đây với bạn bè. Chắc chắn sẽ quay lại nhé.':'I had a great experience here with my friends and will definitely come back.',
    'Khách hàng PlayNest':'PlayNest customer','Quán đẹp, sạch sẽ, dịch vụ tốt, cho 5 sao. Uy tín.':'Beautiful and clean rooms with good service. Five stars.','Phòng mới sạch đẹp, nhiều hạng phòng và khuyến mãi.':'Clean new rooms with several room options and promotions.',
    'Quản lý và nhân viên nhiệt tình, vì thấy gần nhà nên chạy qua thử mà ngồi 2 tiếng đồng hồ lận. Quản lý bảo vẫn sẽ gia tăng các game mà riêng các game hiện có đã hay khủng rồi. Mọi người qua thử trải nghiệm coi, oke lắm á.':'The manager and staff were very helpful. I stopped by to try it and stayed for two hours. The game library is already great and more games are coming.',
    'Đã đánh giá PlayNest 5 sao trên Google.':'Rated PlayNest five stars on Google.','Khách hàng yêu thích PlayNest':'Why customers love PlayNest','PlayNest mang đến không gian giải trí riêng tư với PS5, Nintendo, Netflix và những tiện nghi dành cho cặp đôi, hội bạn.':'PlayNest offers private entertainment rooms with PS5, Nintendo, Netflix and amenities for couples and groups.',
    'Khám phá PlayNest':'Explore PlayNest','Không gian phòng':'Our rooms','Bảng giá':'Pricing','Thông tin hữu ích':'Useful information','Điều khoản dịch vụ':'Terms of service','Bài viết PlayNest':'PlayNest blog','Chính sách riêng tư':'Privacy policy','Ưu đãi & combo':'Offers & combos','Gợi ý trò chơi':'Game recommendations','Câu hỏi thường gặp':'FAQs',
    'Để PlayNest gọi lại cho bạn':'Request a call from PlayNest','Để lại số điện thoại để PlayNest tư vấn phòng, lịch trống và game phù hợp với bạn.':'Leave your phone number and we will help you choose a room, time and suitable games.','Yêu cầu gọi lại':'Request a callback','© 2026 PlayNest. Đã đăng ký bản quyền.':'© 2026 PlayNest. All rights reserved.'
  };
  function translate(){
    document.documentElement.lang='en';document.title=en[document.title]||document.title;
    var walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT),node;
    while((node=walker.nextNode())){var value=node.nodeValue,key=value.trim();if(key&&en[key])node.nodeValue=value.replace(key,en[key]);}
    document.querySelectorAll('[placeholder],[aria-label],[title]').forEach(function(el){['placeholder','aria-label','title'].forEach(function(a){var v=el.getAttribute(a);if(v&&en[v])el.setAttribute(a,en[v]);});});
  }
  window.PlayNestLanguage={set:function(next){try{localStorage.setItem(KEY,next);}catch(e){}var url=new URL(location.href);url.searchParams.delete('lang');location.href=url.pathname+url.search+url.hash;}};
  document.addEventListener('DOMContentLoaded',function(){
    if(language==='en'){try{translate();}finally{document.documentElement.style.visibility='visible';}}
    var button=document.createElement('button');button.type='button';button.className='playnest-language-switcher';button.textContent=language==='en'?'VI':'EN';button.setAttribute('aria-label',language==='en'?'Switch to Vietnamese':'Switch to English');button.onclick=function(){window.PlayNestLanguage.set(language==='en'?'vi':'en');};document.body.appendChild(button);
  });
})();
