CREATE TABLE ibex_user (
    id SERIAL NOT NULL PRIMARY KEY,
    username VARCHAR NOT NULL UNIQUE
        CHECK ( username ~* '^[A-Za-z0-9_-]+$' ), -- Keep in sync with mkdb.sql.
    password VARCHAR NOT NULL,
    email_address VARCHAR,
    active BOOLEAN NOT NULL
);
CREATE TABLE role (
    id SERIAL NOT NULL PRIMARY KEY,
    role VARCHAR NOT NULL
);
CREATE TABLE user_role (
    user_id INTEGER NOT NULL,
    role_id INTEGER NOT NULL,
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (user_id) REFERENCES ibex_user(id),
    FOREIGN KEY (role_id) REFERENCES role(id)
);

CREATE RULE user_del AS ON DELETE TO ibex_user
    DO (
        DELETE FROM user_role WHERE user_id = OLD.id;
    );