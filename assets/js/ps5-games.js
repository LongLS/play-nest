window.ps5Games = [
  { name: "A Way Out", players: "1-2 người", genres: ["Phiêu lưu", "Hành động"] },
  { name: "Asphalt Legends", players: "1-4 người", genres: ["Đua xe"] },
  { name: "Astro’s Playroom", players: "1 người", genres: ["Phiêu lưu"] },
  { name: "Biped", players: "1-2 người", genres: ["Phiêu lưu"] },
  { name: "Cat Quest III", players: "1-2 người", genres: ["Hành động", "Phiêu lưu"] },
  { name: "Disney Speedstorm", players: "1-4 người", genres: ["Đua xe"] },
  { name: "eFootball™", players: "1-4 người", genres: ["Thể thao"] },
  { name: "FC26", players: "1-4 người", genres: ["Thể thao"] },
  { name: "Human Fall Flat", players: "1-2 người", genres: ["Phiêu lưu"] },
  { name: "It Takes Two™", players: "1-2 người", genres: ["Phiêu lưu", "Phối hợp"] },
  { name: "LEGO Horizon Adventures™", players: "1-2 người", genres: ["Phiêu lưu"] },
  { name: "Marvel's Spider-Man 2", players: "1 người", genres: ["Hành động", "Phiêu lưu"] },
  { name: "Mortal Kombat™ 1", players: "1-2 người", genres: ["Đối kháng", "Hành động"] },
  { name: "Nickelodeon All-Star Brawl 2", players: "1-4 người", genres: ["Đối kháng", "Hành động"] },
  { name: "ODDBALLERS", players: "1-4 người", genres: ["Đối kháng"] },
  { name: "Overcooked! All You Can Eat", players: "1-4 người", genres: ["Phối hợp", "Nấu ăn"] },
  { name: "Phogs", players: "1-2 người", genres: ["Phối hợp"] },
  { name: "PlateUp!", players: "1-4 người", genres: ["Phối hợp", "Nấu ăn"] },
  { name: "Rabbids Party of Legends", players: "1-4 người", genres: ["Party"] },
  { name: "Rayman® Legends", players: "1-4 người", genres: ["Phiêu lưu"] },
  { name: "REANIMAL", players: "1-2 người", genres: ["Kinh dị", "Phối hợp", "Phiêu lưu"] },
  { name: "Sackboy: A Big Adventure", players: "1-4 người", genres: ["Phiêu lưu", "Đi cảnh"] },
  { name: "Split Fiction", players: "1-2 người", genres: ["Phiêu lưu", "Hành động", "Phối hợp"] },
  { name: "Trials Fusion", players: "1-4 người", genres: ["Thể thao", "Đua xe"] },
  { name: "Trine 4: The Nightmare Prince", players: "1-4 người", genres: ["Phiêu lưu", "Hành động", "Đi cảnh"] },
  { name: "Untitled Goose Game", players: "1-2 người", genres: ["Phiêu lưu"] },
  { name: "Ben 10: Power Trip!", players: "1-2 người", genres: ["Phiêu lưu"] },
  { name: "Bluey: The Videogame", players: "1-4 người", genres: ["Phiêu lưu", "Hành động"] },
  { name: "Brawlout", players: "1-4 người", genres: ["Đối kháng", "Hành động"] },
  { name: "DEAD OR ALIVE 5", players: "1-4 người", genres: ["Đối kháng", "Hành động"] },
  { name: "Gigantosaurus", players: "1-4 người", genres: ["Thể thao", "Tiệc tùng"] },
  { name: "GTA5", players: "1 người", genres: ["Phiêu lưu", "Hành động"] },
  { name: "Jumanji", players: "1-4 người", genres: ["Phiêu lưu", "Hành động"] },
  { name: "Monopoly Madness", players: "1-4 người", genres: ["Party", "Gia đình"] },
  { name: "Monster Jam Showdown", players: "1-2 người", genres: ["Thể thao", "Đua xe"] },
  { name: "Pile Up!", players: "1-4 người", genres: ["Mô phỏng", "Chiến thuật"] },
  { name: "Snow Bros. Wonderland", players: "1-4 người", genres: ["Phiêu lưu", "Hành động"] },
  { name: "Tennis World Tour 2", players: "1-4 người", genres: ["Thể thao"] },
  { name: "Trials Fusion", players: "1-4 người", genres: ["Thể thao", "Đua xe"] },
  { name: "Cat Quest II", players: "1-2 người", genres: ["Hành động", "Phiêu lưu"] }
];

window.toPs5ImageSlug = function (name) {
  return name
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[™®]/g, "")
    .replace(/&/g, " and ")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
};
