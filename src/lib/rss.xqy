xquery version "1.0-ml";
module namespace rss="http://marklogic.com/rss";
declare namespace c="http://s.opencalais.com/1/pred/";
declare namespace rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#";
(: declare namespace map = "http://www.w3.org/2005/xpath-functions/map"; :)

declare function rss:fetch($request as xs:string, $encoding as xs:string, $enrich as xs:boolean) 
as item() {

  let $options:=<options xmlns="xdmp:http" xmlns:d="xdmp:document-get">
    <d:encoding>{$encoding}</d:encoding>
    <d:format>xml</d:format>
    <verify-cert>false</verify-cert>
  </options>
  let $response:= xdmp:http-get($request, $options)
  let $pubDate:= current-dateTime()
  let $picture:="[Fn], [D01] [MNn] [Y] [H01]:[m01]:[s01] [Z]"
  let $source_name:=fn:tokenize(fn:tokenize(fn:tokenize($request, "//")[2],"/")[1],"\.")[2]
 
  let $uriMap:=map:map()
  let $newEntry:=
    for $item in $response[2]//item
        let $last-part := fn:tokenize($item/guid, "/")[last()]
        let $guid :=   if (exists($last-part)) then $last-part else sem:uuid-string() (: fn:substring-before($last-part,".")     :)
        
        let $content-for-enrichment:=fn:concat($item//title, $item/description)
        let $semantic_tags:= if($enrich) then rss:get-tags($content-for-enrichment) else element semantic_tags {}

        let $newUri:=fn:concat("/nachricht/",$source_name,"/", $guid, ".xml")
        let $newDoc:=document {
          element item {
            element original {
              $item/@*,
              $item/*
            },
            element envelope {
              element type { "rss" },
              element date_time {$pubDate},
              element source { rss:capitalize-first($source_name)},
              element semantic_tags {$semantic_tags/tags}
            }
          }
        }
        return map:put($uriMap,$newUri,$newDoc) 
    return $uriMap
};  

declare function persistDocs ($uriMap as item()) {
  let $uris:=map:keys($uriMap)
  let $permissions:=(xdmp:permission("k-dashboard-role", "read"),
        xdmp:permission("k-dashboard-role", "update"))
  let $collections:=("data","data/rss")
  let $log:= xdmp:log($uris)

  for $newUri in $uris
    let $newDoc:=map:get($uriMap,$newUri)
    return if (fn:doc-available($newUri)) 
      then xdmp:log(fn:concat("skipping ", $newUri)) 
      else xdmp:document-insert($newUri,$newDoc,$permissions,$collections)
  
};

declare function rss:capitalize-first
  ( $arg as xs:string? )  as xs:string? {

   concat(upper-case(substring($arg,1,1)),
             substring($arg,2))
 } ;

 declare function rss:fetch-all($enrich as xs:boolean) {
  let $sources:=doc("/config/sources.json")
  for $rss-source in $sources/rss
    let $log:=xdmp:log($rss-source)

    let $uriMap:=rss:fetch($rss-source/link, $rss-source/encoding, $enrich)
    let $persist:="
      xquery version '1.0-ml';
      import module namespace rss = 'http://marklogic.com/rss' at '/lib/rss.xqy';
      declare variable $uriMap as item()* external;
      rss:persistDocs($uriMap)"
    return xdmp:eval($persist,(xs:QName("uriMap"), $uriMap))
 };

 declare function rss:get-tags ( $arg as xs:string)  
as node()* {

    let $options:=
      <options xmlns="xdmp:http">
        <headers>
          <X-AG-Access-Token>xdEEO9vUWTb4wQDCLX9BdldnwRSpt9Lb</X-AG-Access-Token>
          <Content-Type>text/raw</Content-Type>
        </headers>
        <data>
          {$arg}
        </data>
    </options>
    let $uri:="https://api.thomsonreuters.com/permid/calais"
    let $result:=xdmp:http-post($uri ,$options)  
    let $doc:=$result[2]
    let $tags1:= $doc//rdf:Description[rdf:type/@rdf:resource="http://s.opencalais.com/1/type/tag/SocialTag"]/c:name/text()
    let $tags2:= $doc//rdf:Description[starts-with(rdf:type/@rdf:resource,"http://s.opencalais.com/1/type/em/e")]/c:name/text()
    let $tags:= fn:distinct-values(($tags1,$tags2))
    let $newNode:= element semantic_tags {
      for $tag in $tags
        return element tags {
        $tag
        }
      }
    
    
    return $newNode
 

 };
