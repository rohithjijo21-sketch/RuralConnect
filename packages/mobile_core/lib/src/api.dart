import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
class Api {
 final Dio dio;
 final FlutterSecureStorage storage;
 String? access;
 Future<void>? _refreshing;
 Api({Dio? client,FlutterSecureStorage? secureStorage}):dio=client??Dio(BaseOptions(baseUrl:const String.fromEnvironment('API_URL',defaultValue:'http://10.0.2.2:3001/v1'),connectTimeout:const Duration(seconds:10),receiveTimeout:const Duration(seconds:15))),storage=secureStorage??const FlutterSecureStorage();
 Future<void> restore()async{access=await storage.read(key:'access');}
 Future<void> save(Map<String,dynamic> data)async{await storage.write(key:'refresh',value:data['refreshToken'] as String);await storage.write(key:'access',value:data['accessToken'] as String);access=data['accessToken'] as String;}
 Future<void> clear()async{access=null;await storage.delete(key:'refresh');await storage.delete(key:'access');}
 Future<void> _refresh()async{
  final refresh=await storage.read(key:'refresh');if(refresh==null)throw StateError('Please sign in again');
  try{final r=await dio.post('/auth/refresh',data:{'refreshToken':refresh});await save(Map<String,dynamic>.from(r.data as Map));}catch(_){await clear();rethrow;}
 }
 Future<dynamic> request(String path,{String method='GET',dynamic data,Map<String,String>? headers,bool retry=true})async{
  try{return (await dio.request(path,data:data,options:Options(method:method,headers:{if(access!=null)'Authorization':'Bearer $access',...?headers}))).data;}
  on DioException catch(e){
   if(e.response?.statusCode==401&&retry&&access!=null){_refreshing??=_refresh().whenComplete(()=>_refreshing=null);await _refreshing;return request(path,method:method,data:data,headers:headers,retry:false);}
   rethrow;
  }
 }
 Future<void> logout()async{await request('/auth/logout',method:'POST');await clear();}
}
String readableError(Object error){if(error is DioException){final data=error.response?.data;if(data is Map&&data['message']!=null)return data['message'].toString();return 'Network unavailable. Nothing has been confirmed. Try again.';}return error.toString();}
