export const locations=['Pattambi','Ottapalam','Thrithala','Shoranur','Cherpulassery','Perinthalmanna'];
export const categories=['Home care','Transport','Daily needs','Vehicle care','Construction','Rentals','Personal & events'];
export const services=[
{id:'cleaning',name:'House cleaning',category:'Home care',description:'A fresh start for every corner of your home.',price:499,icon:'🧹',type:'fixed',tone:'mint'},
{id:'plumbing',name:'Plumbing',category:'Home care',description:'Leaks, taps, pipes. Leave it to a local expert.',price:249,icon:'🔧',type:'fixed',tone:'blue'},
{id:'electrical',name:'Electrical',category:'Home care',description:'Safe fixes for switches, wiring and fittings.',price:199,icon:'💡',type:'fixed',tone:'yellow'},
{id:'ac',name:'AC service & repair',category:'Home care',description:'Keep your cool with a little professional care.',price:499,icon:'❄️',type:'fixed',tone:'lilac'},
{id:'painting',name:'Painting',category:'Home care',description:'A new colour. A whole new feeling.',price:0,icon:'🎨',type:'quote',tone:'peach'},
{id:'carpentry',name:'Carpentry',category:'Home care',description:'Thoughtful repairs and custom woodwork.',price:0,icon:'🧰',type:'quote',tone:'sand'},
{id:'taxi',name:'Auto & taxi',category:'Transport',description:'Get where you need to be, with a local driver.',price:0,icon:'🚕',type:'transport',tone:'yellow'},
{id:'delivery',name:'Pickup & delivery',category:'Transport',description:'A helping hand getting things from A to B.',price:0,icon:'📦',type:'transport',tone:'peach'},
{id:'lorry',name:'Goods transport',category:'Transport',description:'Room for bigger things. Local goods transport.',price:0,icon:'🚚',type:'goods',tone:'blue'},
{id:'groceries',name:'Grocery assistance',category:'Daily needs',description:'Help with your neighbourhood shopping list.',price:0,icon:'🛒',type:'transport',tone:'mint'},
{id:'laundry',name:'Laundry & ironing',category:'Daily needs',description:'Fresh clothes, one less thing on your list.',price:0,icon:'👕',type:'fixed',tone:'lilac'},
{id:'carwash',name:'Vehicle washing',category:'Vehicle care',description:'A little shine for your everyday ride.',price:399,icon:'🚙',type:'fixed',tone:'blue'},
{id:'roadside',name:'Roadside assistance',category:'Vehicle care',description:'Request help from an available local technician.',price:0,icon:'🔧',type:'emergency',tone:'yellow'},
{id:'masonry',name:'Masonry & tile work',category:'Construction',description:'Skilled hands for your next building project.',price:0,icon:'🧱',type:'quote',tone:'peach'},
{id:'equipment',name:'Tools & equipment',category:'Rentals',description:'The right tools, for just as long as you need.',price:0,icon:'🧰',type:'rental',tone:'sand'},
{id:'events',name:'Event equipment',category:'Rentals',description:'Chairs, tables and equipment for your gathering.',price:0,icon:'🎉',type:'rental',tone:'lilac'},
{id:'photography',name:'Photography',category:'Personal & events',description:'Keep the moments that matter, beautifully.',price:0,icon:'📷',type:'quote',tone:'mint'},
{id:'computer',name:'Computer repair',category:'Personal & events',description:'Get your everyday technology working again.',price:299,icon:'💻',type:'fixed',tone:'blue'}];
export const workflow={requested:['confirmed','quote_sent','cancelled'],quote_sent:['confirmed','requested','cancelled'],confirmed:['on_the_way','cancelled'],on_the_way:['arrived','cancelled'],arrived:['work_started','cancelled'],work_started:['work_paused','work_completed','disputed'],work_paused:['work_started','cancelled'],work_completed:['disputed'],disputed:['work_completed','cancelled']};
