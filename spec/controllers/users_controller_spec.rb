require File.dirname(__FILE__) + '/../spec_helper'

describe UsersController do
  define_models :users

  before do
    @local = mock_model(Local)
    @local.stub!(:destroyed?).and_return(false)
    @company_size = mock_model(CompanySize)
    @responsability = mock_model(Responsability)
    Local.stub!(:find).and_return(@local)
    CompanySize.stub!(:find).and_return(@company_size)
    Responsability.stub!(:find).and_return(@responsability)
  end

  it 'does not allow confirmation on create' do
    lambda do
      post 'create', :confirmation => "anystring"
      response.should redirect_to(root_url)
    end.should_not change(User, :count)
  end

  it 'allows signup' do
    lambda do
      controller.stub!(:validate_recap).and_return(true)
      create_user
      response.should be_redirect
    end.should change(User, :count).by(1)
  end
  
  it 'disallows signup if captcha is incorrect' do
    lambda do
      controller.stub!(:validate_recap).and_return(false)
      create_user
    end.should_not change(User, :count)
  end

  it 'requires login on signup' do
    lambda do
      create_user(:login => nil)
      assigns[:user].errors.on(:login).should_not be_nil
      flash[:error].should_not be_nil
    end.should_not change(User, :count)
  end

  it 'requires password on signup' do
    lambda do
      create_user(:password => nil)
      assigns[:user].errors.on(:password).should_not be_nil
      flash[:error].should_not be_nil
    end.should_not change(User, :count)
  end

  it 'requires password confirmation on signup' do
    lambda do
      create_user(:password_confirmation => nil)
      assigns[:user].errors.on(:password_confirmation).should_not be_nil
      flash[:error].should_not be_nil
    end.should_not change(User, :count)
  end

  it 'requires email on signup' do
    lambda do
      create_user(:email => nil)
      assigns[:user].errors.on(:email).should_not be_nil
      flash[:error].should_not be_nil
    end.should_not change(User, :count)
  end

  # it 'requires local on signup' do
  #   lambda do
  #     create_user(:local_id => nil)
  #     assigns[:user].errors.on(:local).should_not be_nil
  #     flash[:error].should_not be_nil
  #   end.should_not change(User, :count)
  # end

  # it 'requires working-since on signup' do
  #   lambda do
  #     create_user(:working_since => nil)
  #     assigns[:user].errors.on(:working_since).should_not be_nil
  #     flash[:error].should_not be_nil
  #   end.should_not change(User, :count)
  # end

  it 'activates user' do
    sites(:default).users.authenticate(users(:pending).login, 'test').should_not be_nil
    get :activate, :activation_code => users(:pending).activation_code
    response.should redirect_to('/')
    sites(:default).users.authenticate(users(:pending).login, 'test').should == users(:pending)
    flash[:notice].should_not be_nil
  end

  it 'does not activate user without key' do
    get :activate
    flash[:notice].should be_nil
  end

  it 'does not activate user with blank key' do
    get :activate, :activation_code => ''
    flash[:notice].should be_nil
  end

  it 'activates the first user as admin' do
    User.delete_all
    controller.stub!(:validate_recap).and_return(true)
    create_user
    user = User.find_by_login('quire')
    user.register!
    user.activate!
    user.active?.should == true
    user.admin?.should == true
  end

  it "sends an email to the user on create" do
    controller.stub!(:validate_recap).and_return(true)
    create_user :login => "admin", :email => "admin@example.com"
    response.should be_redirect
    lambda{ create_user }.should change(ActionMailer::Base.deliveries, :size).by(1)
  end
  
  it "prepares for password reset" do
    user = mock_model(User)
    user.should_receive(:generate_lost_password_secret)
    user.should_receive(:save)
    User.should_receive(:find_by_email).and_return(user)
    UserMailer.should_receive(:deliver_remember_password)
    post :remember_password, {:email => 'jack@provider.com'}
  end
  
  it "resets the password" do
    user = mock_model(User)
    user.should_receive(:update_attributes).and_return(true)
    User.should_receive(:find_by_lost_password_secret).and_return(user)
    post :reset_password_confirmation, :user => {}
  end
  
  it  "should resend registration mail" do
    user = mock_model(User)
    controller.should_receive(:current_user).and_return(user)
    UserMailer.should_receive(:deliver_signup_notification).with(user)

    get :resend_confirmation_mail
    
    flash[:notice].should == I18n.t("txt.mail_sent")
    response.should redirect_to(root_path)    
  end

  def create_user(options = {})
    post :create, :user => { :login => 'quire', :email => 'quire@example.com',
      :password => 'monkey', :password_confirmation => 'monkey', :local_id => 1,
      :working_since => "2000", :signature => 'Programmer', :signature_html => '<p>Programmer</p>'}.merge(options)
  end
end

describe UsersController, "GET #index" do
  define_models :stubbed
  before do
    current_site :default
    @controller.stub!(:current_site).and_return(@site)
  end

  act! { get :index, :page => 2 }

  it "should make a paginated list of users available as @users" do
    @site.users.should_receive(:paginate).with(:page => 2).and_return "users"
    acting { assigns(:users).should == "users" }
  end

  describe "with search parameter" do
    define_models :stubbed
    act! { get :index, :q => "bob" }
    define_models do
      model User do
        stub :bob, :display_name => "Bob", :login => "robert", :signature => 'Programmer', :signature_html => '<p>Programmer</p>'
        stub :rob, :display_name => "Robert", :login => "bob", :signature => 'Programmer', :signature_html => '<p>Programmer</p>'
        stub :robby, :display_name => "Robby", :login => "robby", :signature => 'Programmer', :signature_html => '<p>Programmer</p>'
      end
    end
    it "should find users by name" do
      acting
      assigns(:users).should include(users(:bob))
    end
    it "should find users by login" do
      acting
      assigns(:users).should include(users(:rob))
    end
    it "should not include non-matching users" do
      acting
      assigns(:users).should_not include(users(:robby))
    end
  end
end

describe UsersController, "PUT #make_admin" do
  before do
    login_as :admin
    current_site :default
    @attributes = {'login' => "Default"}
  end

  describe UsersController, "(as admin, successful)" do
    define_models :users

    it "sets admin" do
      user = users(:default)
      user.admin.should be_false
      put :make_admin, :id => users(:default).id, :user => { :admin => "1" }
      user.reload.admin.should be_true
    end

    it "unsets admin" do
      user = users(:default)
      user.update_attribute :admin, true
      user.admin.should be_true
      put :make_admin, :id => users(:default).id, :user => { }
      user.reload.admin.should be_false
    end
  end
end

describe UsersController, "PUT #update" do
  define_models :users
  before do
    login_as :default
    current_site :default
    @attributes = {'login' => "Default"}
  end

  describe UsersController, "(successful save)" do
    define_models
    act! { put :update,{ :id => @user.id, :user => @attributes }}

    before do
      @user.stub!(:save).and_return(true)
    end

    it_assigns :user, :flash => { :notice => :not_nil }
    it_redirects_to { settings_path }

    describe "updating from edit form" do
      define_models :stubbed
      %w(display_name website bio).each do |field|
        it "should update #{field}" do
          put :update, :id => @user.id, :user => { field => "test" }
          assigns(:user).attributes[field].should == "test"
        end
      end
      it "should update openid_url" do
        put :update, :id => @user.id, :user => { 'openid_url' => 'test' }
        assigns(:user).attributes['openid_url'].should == 'http://test/'
      end
    end
  end

  describe UsersController, "(successful save, xml)" do
    define_models
    act! { put :update, :id => @user.id, :user => @attributes, :format => 'xml' }

    before do
      @user.stub!(:save).and_return(true)
    end

    it_assigns :user
    it_renders :blank
  end

  describe UsersController, "(unsuccessful save)" do
    define_models
    act! { put :update, :id => @user.id, :user => {:email => ''} }

    it_assigns :user
    it_renders :template, :edit
  end

  describe UsersController, "(unsuccessful save, xml)" do
    define_models
    act! { put :update, :id => @user.id, :user => {:email => ''}, :format => 'xml' }

    it_assigns :user
    it_renders :xml, :status => :unprocessable_entity do
      assigns(:user).errors.to_xml
    end
  end
end
