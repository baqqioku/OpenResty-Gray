#killall nginx

rm *temp -rf

/usr/local/openresty/nginx/sbin/nginx -p `pwd` -c conf/nginx.conf  
/usr/local/openresty/nginx/sbin/nginx -p `pwd` -c conf/stable.conf 
/usr/local/openresty/nginx/sbin/nginx -p `pwd` -c conf/beta1.conf  
/usr/local/openresty/nginx/sbin/nginx -p `pwd` -c conf/beta2.conf  
/usr/local/openresty/nginx/sbin/nginx -p `pwd` -c conf/beta3.conf  
/usr/local/openresty/nginx/sbin/nginx -p `pwd` -c conf/beta4.conf  
