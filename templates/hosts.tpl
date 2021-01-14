[ipa]
%{ for ip in ipa ~}
${ip}
%{ endfor ~}
[master]
%{ for ip in master ~}
${ip}
%{ endfor ~}
[worker]
%{ for ip in worker ~}
${ip}
%{ endfor ~}