
// fetch('/poll/3')
//   .then((cnt) => {
    // const reader = cnt.body.getReader()
    // reader.read().then(({ done, value }) => {
    //   if (done) {
    //     console.log('Done!', value)
    //   } else {
    //     console.log('value = ', value)
    //   }
    // })

    const xml = new XMLHttpRequest()
    xml.open('GET', '/poll/4', true)
    xml.timeout = 10000
    xml.responseType = 'blob'
    xml.onload = function() {
      console.log('loaded')
    }
    xml.onreadystatechange = function() {
      // if (xml.readyState == 3) {
        console.log('response = ', xml.response)

      // }
      // console.log('state = ', xml.readyState, ' resp = ', xml.response)
    }

    xml.send()

    // console.log('cnt = ', cnt)
    // window.cnt = cnt
    barfoo.innerHTML = 'hey'
  // })
