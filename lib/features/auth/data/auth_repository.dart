import '../../../core/constants/api_constants.dart';
import '../../../core/models/user_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/auth_storage.dart';

class AuthRepository {
  final _dio = ApiClient.instance.dio;

  Future<UserModel> login(String username, String password) async {
    final response = await _dio.post(
      ApiConstants.login,
      data: {'usuario': username, 'password': password},
    );
    final user = UserModel.fromLoginResponse(response.data);
    await AuthStorage.saveUser(user);
    return user;
  }

  Future<void> logout() async {
    await AuthStorage.clear();
  }

  Future<UserModel?> getStoredUser() => AuthStorage.getUser();
}
