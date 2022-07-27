// const superagent = require('superagent');
//
// superagent
//     .get('https://caramel.pancakeswap.com/mcv1/farms?filter=active') //这里的URL也可以是绝对路径
//     .end(function(req, res){
//
//         let arr = JSON.parse(res.text);
//         //console.log(arr);
//         let total = 2, str = '137,138';
//         for (let item of arr) {
//             if (parseFloat(item['multiplier']) > 0) {
//                 total+=parseInt(item['multiplier'])*100;
//                 str += ',' + item['pid'];
//             }
//         }
//         console.log(total);
//         console.log(str);
//     });

con