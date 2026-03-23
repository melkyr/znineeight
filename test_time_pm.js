function getTestDate() {
    const d = new Date();
    d.setHours(21, 15, 7);
    return d;
}

const testDate = getTestDate();

console.log("Locale (en-GB):", testDate.toLocaleTimeString('en-GB'));
console.log("Manual (padStart):", [testDate.getHours(), testDate.getMinutes(), testDate.getSeconds()].map(v => v.toString().padStart(2, '0')).join(':'));
console.log("toTimeString (slice):", testDate.toTimeString().slice(0, 8));
console.log("Intl.DateTimeFormat (en-GB):", new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(testDate));
